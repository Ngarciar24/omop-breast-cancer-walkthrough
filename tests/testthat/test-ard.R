# ---------------------------------------------------------------------------
# Tests for the Analysis Results Data (M6). These need run_all.R first.
#
#   1  Every number in the report tables equals the matching ARD value.
#   2  The ARD equals a recomputation from adsl_like with base R.
#   3  The Parquet and CSV files hold the same rows.
#   4  The report never reads patient-level data.
# ---------------------------------------------------------------------------

ard_file <- function(file) repo_path("results", "ard", file)

read_ard_parquet <- function(file) as.data.frame(arrow::read_parquet(ard_file(file)))

skip_without_ard <- function() {
  skip_if_not(file.exists(ard_file("m6_table1_ard.parquet")), "ARD not written yet")
}

# Numbers in a table cell such as "63.5 (52.5, 68.0)" or "24 (19.4%)".
numbers_in <- function(cell) as.numeric(regmatches(cell, gregexpr("[0-9]+(\\.[0-9]+)?", cell))[[1]])
decimals_in <- function(cell) {
  tokens <- regmatches(cell, gregexpr("[0-9]+(\\.[0-9]+)?", cell))[[1]]
  nchar(sub("^[0-9]+\\.?", "", tokens))
}

test_that("every number in Table 1 equals the ARD value it came from", {
  skip_without_ard()
  ard <- read_ard_parquet("m6_table1_ard.parquet")
  table <- table1_from_ard(ard)
  groups <- c(NA, treatment_levels)

  # Walk the table in the same order table1_from_ard builds it, and find the
  # ARD statistics behind every cell.
  expected_for <- function(variable, level, group) {
    stat <- function(name, lvl = NA) ard_value(ard, group, variable, name, lvl, "stat")
    if (variable %in% table1_continuous) {
      c(stat("median"), stat("p25"), stat("p75"))
    } else {
      c(stat("n", level), 100 * stat("p", level))
    }
  }

  checked <- 0
  row <- 0
  for (variable in names(table1_labels)) {
    levels <- if (variable %in% table1_categorical) {
      row <- row + 1  # the label row has no numbers
      unique(ard$variable_level[ard$variable == variable])
    } else if (variable %in% table1_flags) {
      "Y"
    } else {
      NA
    }
    for (level in levels) {
      row <- row + 1
      for (g in seq_along(groups)) {
        cell <- table[row, g + 1]
        shown <- numbers_in(cell)
        expected <- expected_for(variable, level, groups[g])
        # A shown number may be rounded. It must be within half of its last digit.
        tolerance <- 0.5 * 10^(-decimals_in(cell)) + 1e-9
        expect_true(all(abs(shown - expected) <= tolerance),
                    info = paste(variable, level, groups[g], cell))
        checked <- checked + 1
      }
    }
  }
  # 12 rows with numbers. Age, 4 age groups, 2 sexes, 3 flags, prior
  # observation and index year.
  expect_equal(checked, 12 * length(groups))
})

test_that("the Table 1 ARD equals a base R recomputation from adsl_like", {
  skip_without_ard()
  cdm <- open_cdm()
  on.exit(close_cdm(cdm))
  adsl <- DBI::dbReadTable(CDMConnector::cdmCon(cdm), "adsl_like")
  data <- table1_input(adsl)
  ard <- read_ard_parquet("m6_table1_ard.parquet")

  for (group in c(NA, treatment_levels)) {
    rows <- if (is.na(group)) data else data[data$FTRTCLS == group, ]

    for (variable in table1_continuous) {
      x <- rows[[variable]]
      expect_equal(ard_value(ard, group, variable, "median", column = "stat"), median(x))
      # cards uses quantile type 2.
      expect_equal(ard_value(ard, group, variable, "p25", column = "stat"),
                   unname(quantile(x, 0.25, type = 2)))
      expect_equal(ard_value(ard, group, variable, "p75", column = "stat"),
                   unname(quantile(x, 0.75, type = 2)))
    }
    for (variable in c(table1_categorical, table1_flags)) {
      counts <- table(rows[[variable]])
      levels <- if (variable %in% table1_flags) "Y" else names(counts)
      for (level in levels) {
        expect_equal(ard_value(ard, group, variable, "n", level, "stat"),
                     as.numeric(counts[[level]]), info = paste(variable, level, group))
        expect_equal(ard_value(ard, group, variable, "p", level, "stat"),
                     as.numeric(counts[[level]]) / nrow(rows))
      }
    }
  }
})

test_that("the survival ARD equals survfit at every time", {
  skip_without_ard()
  cdm <- open_cdm()
  on.exit(close_cdm(cdm))
  con <- CDMConnector::cdmCon(cdm)
  fits <- os_fits(DBI::dbReadTable(con, "adsl_like"), DBI::dbReadTable(con, "adtte_like"))
  ard <- read_ard_parquet("m6_survival_ard.parquet")

  for (name in names(fits)) {
    from_ard <- survival_table_from_ard(ard, survival_analyses[[name]])
    from_fit <- km_summary(fits[[name]], times = unique(from_ard$time_days))
    both <- merge(from_ard, from_fit, by = c("strata", "time_days"),
                  suffixes = c("_ard", "_fit"))

    expect_equal(nrow(both), nrow(from_ard), info = name)
    expect_equal(both$n_risk_ard, both$n_risk_fit, info = name)
    expect_equal(both$survival_ard, both$survival_fit, info = name)
    expect_equal(both$lower_95_ard, both$lower_95_fit, info = name)
  }
})

test_that("Parquet and CSV hold the same rows", {
  skip_without_ard()
  for (stem in c("m6_table1_ard", "m6_survival_ard")) {
    from_parquet <- read_ard_parquet(paste0(stem, ".parquet"))
    # stat_fmt is text such as "58.0". Read it as text, or read.csv makes it 58.
    from_csv <- read.csv(ard_file(paste0(stem, ".csv")), na.strings = "NA",
                         colClasses = c(stat_fmt = "character"))
    expect_equal(nrow(from_parquet), nrow(from_csv), info = stem)
    expect_equal(from_parquet$stat, from_csv$stat, info = stem)
    expect_equal(from_parquet$stat_name, from_csv$stat_name, info = stem)
    expect_equal(from_parquet$stat_fmt, from_csv$stat_fmt, info = stem)
  }
})

test_that("the report never reads patient-level data", {
  report <- readLines(repo_path("report", "report.qmd"))
  forbidden <- c("dbConnect", "dbReadTable", "dbGetQuery", "open_cdm", "duckdb",
                 "adsl_like <-", "adtte_like <-")
  for (pattern in forbidden) {
    expect_false(any(grepl(pattern, report, fixed = TRUE)), info = pattern)
  }
})
