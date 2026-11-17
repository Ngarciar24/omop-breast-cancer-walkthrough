# ---------------------------------------------------------------------------
# ard_helpers.R
#
# Analysis Results Data (ARD) stores every statistic as one row, with the
# group, variable, statistic name and value. Tables are then only a reshaping
# of those rows. Nothing in a table is recomputed from patient data.
#
# This file has three parts.
#   Building the ARD with cards and cardx (used by R/60_ard.R)
#   Flattening it into plain columns for Parquet and CSV
#   Laying out report tables from the flat ARD (used by the report and tests)
#
# It uses treatment_levels, survival_analyses and days_per_year from
# R/survival_helpers.R, so load that file first.
# ---------------------------------------------------------------------------

# --- Table 1 --------------------------------------------------------------

table1_labels <- c(
  AGE      = "Age at index, years",
  AGEGR1   = "Age group",
  SEX      = "Sex",
  CMIHDFL  = "Ischaemic heart disease before index",
  CMCVDFL  = "Cerebrovascular disease before index",
  CMAFFL   = "Atrial fibrillation before index",
  PRIOROBS = "Prior observation, days",
  INDEXYR  = "Index year"
)
table1_continuous <- c("AGE", "PRIOROBS", "INDEXYR")
table1_categorical <- c("AGEGR1", "SEX")
table1_flags <- c("CMIHDFL", "CMCVDFL", "CMAFFL")

# Factors fix the order of groups and levels. A flag is a factor with both
# levels, so a group with no "Y" still gets a count of 0.
table1_input <- function(adsl) {
  yn <- function(x) factor(x, levels = c("N", "Y"))
  data.frame(
    FTRTCLS  = factor(adsl$FTRTCLS, levels = treatment_levels),
    AGE      = adsl$AGE,
    AGEGR1   = factor(adsl$AGEGR1, levels = c("<50", "50-64", "65-74", ">=75")),
    SEX      = factor(adsl$SEX, levels = c("F", "M")),
    CMIHDFL  = yn(adsl$CMIHDFL),
    CMCVDFL  = yn(adsl$CMCVDFL),
    CMAFFL   = yn(adsl$CMAFFL),
    PRIOROBS = adsl$PRIOROBS,
    INDEXYR  = as.numeric(format(adsl$INDEXDT, "%Y"))
  )
}

# Medians and quartiles, n and %. No tests, on purpose.
# cards computes p25 and p75 with quantile(type = 2).
table1_ard <- function(data) {
  ard <- cards::ard_stack(
    data,
    .by = FTRTCLS,
    cards::ard_continuous(
      variables = dplyr::all_of(table1_continuous),
      statistic = ~ cards::continuous_summary_fns(c("median", "p25", "p75"))
    ),
    cards::ard_categorical(variables = dplyr::all_of(table1_categorical)),
    cards::ard_dichotomous(
      variables = dplyr::all_of(table1_flags),
      value = list(CMIHDFL = "Y", CMCVDFL = "Y", CMAFFL = "Y")
    ),
    .overall = TRUE,
    .total_n = TRUE
  )
  # Age keeps one decimal. Days and years are whole numbers.
  ard <- cards::update_ard_fmt_fun(ard, variables = c(PRIOROBS, INDEXYR),
                                   stat_names = c("median", "p25", "p75"),
                                   fmt_fun = 0)
  cards::apply_fmt_fun(ard)
}

# --- Survival -------------------------------------------------------------

# Estimate, 95% CI and number at risk at each time, for every fit.
survival_ard <- function(fits, times_days) {
  do.call(rbind, lapply(names(fits), function(name) {
    flat <- flatten_ard(cardx::ard_survival_survfit(fits[[name]], times = times_days))
    flat$analysis <- survival_analyses[[name]]
    flat
  }))
}

# --- Flattening -----------------------------------------------------------
# cards keeps some columns as lists, because a statistic can be a number or
# text. Parquet and CSV need plain columns. stat holds the number (NA for
# text such as the CI type) and stat_fmt holds the formatted text. The
# formatting functions are dropped. The run stops if cards recorded an error.

flatten_ard <- function(ard) {
  ard <- as.data.frame(ard)
  errors <- ard$error[!vapply(ard$error, is.null, logical(1))]
  if (length(errors) > 0) stop("cards recorded errors: ", paste(unlist(errors), collapse = "; "))

  as_text <- function(column) {
    vapply(column, function(v) {
      if (is.null(v) || length(v) == 0) NA_character_ else as.character(v)[1]
    }, character(1))
  }
  as_number <- function(column) {
    vapply(column, function(v) {
      if (is.numeric(v) && length(v) == 1) as.numeric(v) else NA_real_
    }, numeric(1))
  }
  stat_fmt <- if ("stat_fmt" %in% names(ard)) as_text(ard$stat_fmt) else as_text(ard$stat)

  # An ungrouped result, such as a survival curve for everyone, has no group
  # columns at all. They become NA, which means "overall".
  if (!"group1" %in% names(ard)) {
    ard$group1 <- NA_character_
    ard$group1_level <- list(NULL)
  }

  data.frame(
    group1         = ard$group1,
    group1_level   = as_text(ard$group1_level),
    variable       = ard$variable,
    variable_level = as_text(ard$variable_level),
    context        = ard$context,
    stat_name      = ard$stat_name,
    stat_label     = ard$stat_label,
    stat           = as_number(ard$stat),
    stat_fmt       = stat_fmt
  )
}

# --- Tables from the flat ARD ---------------------------------------------

# One value from the ARD. group NA means the overall column.
ard_value <- function(ard, group, variable, stat_name, level = NA, column = "stat_fmt") {
  keep <- ard$variable == variable & ard$stat_name == stat_name &
    (if (is.na(group)) is.na(ard$group1_level) else ard$group1_level %in% group) &
    (if (is.na(level)) is.na(ard$variable_level) else ard$variable_level %in% level)
  value <- ard[[column]][keep]
  if (length(value) != 1) stop("Expected one ARD row for ", variable, " ", stat_name,
                               " ", group, " ", level, ", found ", length(value))
  value
}

# Table 1 laid out from the ARD. Columns are Overall and each treatment group,
# with N in the header. Rows follow table1_labels.
table1_from_ard <- function(ard) {
  groups <- c(NA, treatment_levels)
  group_n <- c(
    ard_value(ard, NA, "..ard_total_n..", "N"),
    vapply(treatment_levels, function(g) ard_value(ard, NA, "FTRTCLS", "n", level = g),
           character(1))
  )
  headers <- paste0(c("Overall", treatment_levels), " N = ", group_n)

  cells <- function(make_cell) vapply(groups, make_cell, character(1))
  continuous_cell <- function(variable) {
    function(g) {
      paste0(ard_value(ard, g, variable, "median"), " (",
             ard_value(ard, g, variable, "p25"), ", ",
             ard_value(ard, g, variable, "p75"), ")")
    }
  }
  count_cell <- function(variable, level) {
    function(g) {
      paste0(ard_value(ard, g, variable, "n", level), " (",
             ard_value(ard, g, variable, "p", level), "%)")
    }
  }

  rows <- list()
  for (variable in names(table1_labels)) {
    label <- table1_labels[[variable]]
    if (variable %in% table1_continuous) {
      rows[[length(rows) + 1]] <- c(label, cells(continuous_cell(variable)))
    } else if (variable %in% table1_flags) {
      rows[[length(rows) + 1]] <- c(label, cells(count_cell(variable, "Y")))
    } else {
      rows[[length(rows) + 1]] <- c(label, rep("", length(groups)))
      levels <- unique(ard$variable_level[ard$variable == variable])
      for (level in levels) {
        rows[[length(rows) + 1]] <- c(paste0("    ", level),
                                      cells(count_cell(variable, level)))
      }
    }
  }

  table <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  names(table) <- c("Characteristic", headers)
  table
}

# Survival table for one analysis, laid out from the flat survival ARD.
survival_table_from_ard <- function(ard, analysis) {
  rows <- ard[ard$analysis == analysis & ard$variable == "time", ]
  rows$strata <- ifelse(is.na(rows$group1_level), "Overall", rows$group1_level)
  keys <- unique(rows[, c("strata", "variable_level")])

  value <- function(strata, time, stat_name) {
    rows$stat[rows$strata == strata & rows$variable_level == time &
                rows$stat_name == stat_name]
  }
  data.frame(
    strata    = keys$strata,
    time_days = as.numeric(keys$variable_level),
    years     = as.numeric(keys$variable_level) / days_per_year,
    n_risk    = mapply(value, keys$strata, keys$variable_level, "n.risk"),
    survival  = mapply(value, keys$strata, keys$variable_level, "estimate"),
    lower_95  = mapply(value, keys$strata, keys$variable_level, "conf.low"),
    upper_95  = mapply(value, keys$strata, keys$variable_level, "conf.high"),
    row.names = NULL
  )
}
