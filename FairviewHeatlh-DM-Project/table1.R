library(DBI)
library(odbc)
library(dplyr)

# --- 1. Connect ---------------------------------------------------------
con <- dbConnect(
  odbc::odbc(),
  Driver   = "SQL Server",
  Server   = "your_server",
  Database = "your_database"
)

# --- 2. Get the data ----------------------
df <- dbGetQuery(con, "SELECT * FROM #patients")

dbDisconnect(con)

# --- 3. Derive variables --------------------------------------------------
obfuscation_threshold <- 20

df <- df %>%
  mutate(
    diabetes_dx_age = as.numeric(difftime(earliest_diabetes_dx_date, dob, units = "days")) / 365.25,
    vital_status    = ifelse(is.na(death_date), "Alive", "Dead")
  )

# --- 4. Suppression logic -------------------------------------------------
# Suppresses any nonzero count below threshold as "<20".
# If that leaves exactly ONE hidden cell in the group, also hides the
# next-smallest cell -- otherwise it could be recovered as (total - known values).
suppress_counts <- function(counts, threshold = obfuscation_threshold) {
  below <- counts > 0 & counts < threshold
  if (sum(below) == 1) {
    candidates <- counts[!below]
    if (length(candidates) > 0) below[names(candidates)[which.min(candidates)]] <- TRUE
  }
  ifelse(below, paste0("<", threshold), as.character(counts))
}

format_cat <- function(var) {
  counts <- table(df[[var]], useNA = "ifany")
  display_n <- suppress_counts(counts)
  pct <- round(100 * counts / sum(counts), 1)
  stat <- ifelse(grepl("<", display_n), display_n, paste0(display_n, " (", pct, "%)"))
  data.frame(Variable = var, Level = names(counts), Statistic = stat)
}

format_cont <- function(var, threshold = obfuscation_threshold) {
  x <- df[[var]]
  n_valid <- sum(!is.na(x))
  stat <- if (n_valid > 0 && n_valid < threshold) {
    paste0("<", threshold)
  } else {
    paste0(round(mean(x, na.rm = TRUE), 1), " (", round(sd(x, na.rm = TRUE), 1), ")")
  }
  data.frame(Variable = var, Level = "Mean (SD)", Statistic = stat)
}

# --- 5. Build the single Table 1 -------------------------------------------------
cat_vars <- c("vital_status", "ethnic_group", "patient_race_1", "language", "legal_sex")

table1 <- bind_rows(
  format_cont("diabetes_dx_age"),
  bind_rows(lapply(cat_vars, format_cat))
)

table1

# --- 6.Review and Export -------------------------------------------------
write.csv(table1, "table1.csv", row.names = FALSE)


###### Code translated to SQL by claude
DECLARE @threshold INT = 20;

WITH base AS (
  SELECT
  mdm_link_id,
  dob,
  death_date,
  earliest_diabetes_dx_date,
  DATEDIFF(DAY, dob, earliest_diabetes_dx_date) / 365.25 AS diabetes_dx_age,
  CASE WHEN death_date IS NULL THEN 'Alive' ELSE 'Dead' END AS vital_status,
  ethnic_group, patient_race_1, language, legal_sex
  FROM #patients
),

long_cat AS (
  SELECT 'vital_status'  AS variable, vital_status  AS level FROM base
  UNION ALL SELECT 'ethnic_group',   ethnic_group   FROM base
  UNION ALL SELECT 'patient_race_1', patient_race_1 FROM base
  UNION ALL SELECT 'language',       language       FROM base
  UNION ALL SELECT 'legal_sex',      legal_sex      FROM base
),

counts AS (
  SELECT variable, level, COUNT(*) AS n
  FROM long_cat
  GROUP BY variable, level
),

flagged AS (
  SELECT *, CASE WHEN n > 0 AND n < @threshold THEN 1 ELSE 0 END AS is_below
  FROM counts
),

ranked AS (
  SELECT *,
  SUM(is_below) OVER (PARTITION BY variable) AS num_below,
  ROW_NUMBER() OVER (PARTITION BY variable, is_below ORDER BY n ASC) AS rn
  FROM flagged
),

suppressed AS (
  SELECT variable, level, n,
  CASE
  WHEN is_below = 1 THEN 1
  WHEN num_below = 1 AND is_below = 0 AND rn = 1 THEN 1  -- secondary suppression
  ELSE 0
  END AS suppress
  FROM ranked
),

categorical_table AS (
  SELECT
  variable AS Variable,
  level    AS Level,
  CASE WHEN suppress = 1
  THEN '<' + CAST(@threshold AS VARCHAR)
  ELSE CAST(n AS VARCHAR) + ' (' +
    CAST(ROUND(100.0 * n / SUM(n) OVER (PARTITION BY variable), 1) AS VARCHAR) + '%)'
  END AS Statistic
  FROM suppressed
),

continuous_table AS (
  SELECT
  'diabetes_dx_age' AS Variable,
  'Mean (SD)'       AS Level,
  CASE
  WHEN COUNT(diabetes_dx_age) > 0 AND COUNT(diabetes_dx_age) < @threshold
  THEN '<' + CAST(@threshold AS VARCHAR)
  ELSE CAST(ROUND(AVG(diabetes_dx_age), 1) AS VARCHAR) + ' (' +
    CAST(ROUND(STDEV(diabetes_dx_age), 1) AS VARCHAR) + ')'
  END AS Statistic
  FROM base
)

SELECT * FROM continuous_table
UNION ALL
SELECT * FROM categorical_table
ORDER BY Variable, Level;

