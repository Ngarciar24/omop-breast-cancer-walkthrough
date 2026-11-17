# ---------------------------------------------------------------------------
# survival_helpers.R
#
# Small functions for the M5 survival analyses. The tests use them too.
#
# A note on CNSR. ADaM codes CNSR = 1 for censored and 0 for an event.
# survival::Surv() wants the opposite, 1 for an event. So every Surv() call
# here uses event = 1 - CNSR.
# ---------------------------------------------------------------------------

library(survival)
library(ggplot2)

days_per_year <- 365.25

# Survival, 95% confidence interval and number at risk at chosen times (days).
# extend = TRUE returns a row even after the last follow-up time, with 0 at risk.
km_summary <- function(fit, times) {
  s <- summary(fit, times = times, extend = TRUE)
  strata <- if (is.null(s$strata)) rep("Overall", length(s$time)) else
    sub("^[^=]+=", "", as.character(s$strata))
  data.frame(
    strata = strata,
    time_days = s$time,
    n_risk = s$n.risk,
    n_event_cumulative = ave(s$n.event, strata, FUN = cumsum),
    survival = s$surv,
    lower_95 = s$lower,
    upper_95 = s$upper
  )
}

# Landmark dataset. Keeps people still alive and under observation after the
# landmark day, groups them by treatment on or before that day, and restarts
# the clock at the landmark.
#   adsl  needs USUBJID, FTRTFL, FTRTDT, INDEXDT
#   adtte needs USUBJID, PARAMCD, AVAL, CNSR
landmark_data <- function(adsl, adtte, day = 90) {
  os <- adtte[adtte$PARAMCD == "OS", c("USUBJID", "AVAL", "CNSR")]
  os <- merge(os, adsl[, c("USUBJID", "FTRTFL", "FTRTDT", "INDEXDT")], by = "USUBJID")

  # Still at risk after the landmark. Someone who dies or leaves observation
  # on or before the landmark day cannot be followed from it.
  os <- os[os$AVAL > day, ]

  treated_by_landmark <- !is.na(os$FTRTDT) &
    as.numeric(os$FTRTDT - os$INDEXDT) <= day
  os$group <- ifelse(treated_by_landmark,
                     paste("Treated by day", day),
                     paste("Not treated by day", day))
  os$AVAL_LM <- os$AVAL - day
  os
}

# Kaplan-Meier figure with numbers at risk printed under the x-axis.
km_plot <- function(fit, title, x_label = "Years from index",
                    max_years = 10, risk_every_years = 2) {
  s <- summary(fit, censored = TRUE)
  strata <- if (is.null(s$strata)) rep("Overall", length(s$time)) else
    sub("^[^=]+=", "", as.character(s$strata))
  curve <- data.frame(years = s$time / days_per_year, survival = s$surv, strata = strata)

  # Every curve starts at survival 1 at time 0.
  starts <- data.frame(years = 0, survival = 1, strata = unique(strata))
  curve <- rbind(starts, curve)
  curve <- curve[curve$years <= max_years, ]

  risk_years <- seq(0, max_years, by = risk_every_years)
  risk <- km_summary(fit, times = risk_years * days_per_year)
  risk$years <- risk$time_days / days_per_year

  # Numbers at risk go below the axis title, one line per group. The y values
  # are in survival units, so -0.2 means 20% of the panel height below zero.
  groups <- unique(risk$strata)
  risk$y <- -0.24 - 0.065 * (match(risk$strata, groups) - 1)

  ggplot(curve, aes(x = years, y = survival, colour = strata)) +
    geom_step(linewidth = 0.7) +
    geom_text(data = risk, aes(x = years, y = y, label = n_risk, colour = strata),
              size = 3, show.legend = FALSE) +
    annotate("text", x = -0.3, y = -0.18, label = "Number at risk", hjust = 0, size = 3) +
    scale_x_continuous(breaks = risk_years, limits = c(-0.3, max_years + 0.3)) +
    scale_y_continuous(breaks = seq(0, 1, 0.25), labels = scales::percent) +
    coord_cartesian(ylim = c(0, 1), clip = "off") +
    labs(title = title, x = x_label, y = "Survival", colour = NULL) +
    theme_minimal(base_size = 11) +
    theme(
      legend.position = "top",
      axis.title.x = element_text(margin = margin(t = 4)),
      plot.margin = margin(10, 10, 30 + 22 * length(groups), 10)
    )
}
