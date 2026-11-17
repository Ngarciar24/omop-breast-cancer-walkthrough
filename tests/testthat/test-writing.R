# ---------------------------------------------------------------------------
# Writing rules for the texts in the repository: no semicolons and none of
# the listed hype words.
# ---------------------------------------------------------------------------

texts <- c("README.qmd", "README.md", file.path("docs", "interview-questions.md"),
           file.path("report", "report.qmd"))

test_that("the texts have no semicolons", {
  for (file in texts) {
    path <- do.call(repo_path, as.list(strsplit(file, "/")[[1]]))
    skip_if_not(file.exists(path), paste(file, "not written yet"))
    lines <- readLines(path)
    expect_false(any(grepl(";", lines, fixed = TRUE)), info = file)
  }
})

test_that("the texts avoid hype words", {
  hype <- c("robust", "leverage", "comprehensive", "seamless", "cutting-edge",
            "in my own time")
  for (file in texts) {
    path <- do.call(repo_path, as.list(strsplit(file, "/")[[1]]))
    skip_if_not(file.exists(path), paste(file, "not written yet"))
    text <- tolower(paste(readLines(path), collapse = " "))
    for (word in hype) expect_false(grepl(word, text, fixed = TRUE), info = paste(file, word))
  }
})
