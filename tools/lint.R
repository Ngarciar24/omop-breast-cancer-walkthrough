# ---------------------------------------------------------------------------
# lint.R
#
#   Rscript tools/lint.R
#
# Lint all R code with the settings in .lintr. Exits with status 1 if there is
# any lint, so CI fails on it.
# ---------------------------------------------------------------------------

targets <- c("R", "tests", "tools", "run_all.R")
n_lints <- 0
for (target in targets) {
  lints <- if (dir.exists(target)) lintr::lint_dir(target) else lintr::lint(target)
  if (length(lints) > 0) print(lints)
  n_lints <- n_lints + length(lints)
}

message(n_lints, " lints in ", paste(targets, collapse = ", "))
if (n_lints > 0) quit(status = 1)
