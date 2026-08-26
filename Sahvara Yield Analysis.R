# ==============================================================================

# SAHVARA SUBNATIONAL AGRICULTURAL YIELD COMPARISON

# ==============================================================================

#

# Author: Abel B. S. Gaiya

#

# Description

# -----------

# This script produces a ranked comparison of average agricultural yields across

# first-level administrative units in the Sahvara. Sahvaran units and their CS4

# or NE5 classifications are obtained from Table 5 of the underlying study and

# matched to corresponding administrative units in HarvestStat Africa v1.2.

#

# The analysis identifies the five crops with the greatest average annual

# harvested acreage across the matched Sahvaran units. For each administrative

# unit, it calculates an acreage-weighted average yield for these crops over the

# unit's latest five available HarvestStat years:

#

# average yield = total crop production / total harvested area

#

# This ratio-of-sums approach gives greater weight to crops occupying larger

# harvested areas and avoids treating small and large crops as equally important.

#

# Analytical procedure

# --------------------

# 1. Read the Sahvaran administrative units listed in Table 5.

# 2. Classify each unit as belonging to the CS4 or NE5.

# 3. Match Table 5 unit names to HarvestStat admin-1 names using an explicit

# crosswalk for spelling, accent and administrative-name differences.

# 4. Exclude HarvestStat records identified as outliers (qc_flag = 1), while

# retaining ordinary records and low-variance warnings (qc_flag = 0 or 2).

# 5. Select each matched unit's latest five available harvest years.

# 6. Rank crops by their summed average annual harvested area across units.

# 7. Select the five largest crops and calculate each unit's acreage-weighted

# yield across those crops and years.

# 8. Rank administrative units from the lowest to the highest average yield.

# 9. Highlight CS4 units, NE5 units, administrative-capital units and selected

# commercial-capital units in the resulting chart.

# 10. Export the chart and supporting audit tables.

#

# Default crop basket

# -------------------

# Using the supplied datasets, the five largest crops are:

#

# - Sorghum

# - Millet

# - Cowpea

# - Maize

# - Groundnuts (In Shell)

#

# The crop basket is nevertheless calculated dynamically. It may therefore

# change if the source data, geographic coverage or analytical parameters change.

#

# Required input files

# --------------------

# - hvstat_africa_data_v1.2.csv

#

# Before running the script, update `data_dir` to the folder containing these

# files. The current configuration uses:

#

# C:/Users/user/Desktop/Sahvara

#

# Required R packages

# -------------------

# - tidyverse

# - readxl

# - writexl

# - scales

#

# Install them, if necessary, with:

#

# install.packages(c("tidyverse", "readxl", "writexl", "scales"))

#

# Outputs

# -------

# The script creates a `sahvara_yield_outputs` directory containing:

#

# - sahvara_average_agricultural_yield.png

# - 01_unit_mapping.csv

# - 02_crop_ranking.csv

# - 03_crop_year_observations.csv

# - 04_unit_yield_results.csv

# - sahvara_yield_audit.xlsx

#

# Data-coverage limitations

# -------------------------

# HarvestStat Africa v1.2 does not contain records for Côte d'Ivoire and does

# not provide matched admin-1 observations for several city-level units in

# Table 5. These units are retained in the mapping and results tables as coverage

# gaps but excluded from the ranked chart. The combined Table 5 unit

# "Tiris Zemmour & Inchiri" is represented by Inchiri alone and is explicitly

# marked as a partial geographic match.

#

# Reproducibility

# ---------------

# With the supplied versions of Table 5 and HarvestStat Africa, the script should

# identify 79 Sahvaran units, match and chart 69 of them, and document 10 units

# without matched yield data. Results may differ if the source files are revised.

#

# Suggested citation for HarvestStat Africa

# -----------------------------------------

# Lee, D., Anderson, W., Chen, X., et al. (2025). HarvestStat Africa:

# Harmonized Subnational Crop Statistics for Sub-Saharan Africa.

# Scientific Data. https://doi.org/10.1038/s41597-025-05001-z

#


# ==============================================================================


suppressPackageStartupMessages({
  library(tidyverse)
  library(readxl)
  library(writexl)
  library(scales)
})

# -----------------------------------------------------------------------------
# 1. Paths and analysis settings
# -----------------------------------------------------------------------------

data_dir <- "C:/Users/user/Desktop/Sahvara"

table5_file <- file.path(
  data_dir,
  "Copy of Table 5 Subnational Results MPI 2024.xlsx"
)

harveststat_file <- file.path(
  data_dir,
  "hvstat_africa_data_v1.2.csv"
)

output_dir <- file.path(data_dir, "sahvara_yield_outputs")

table5_sheet <- "Sheet5"
n_crops <- 5
n_recent_years <- 5

missing_inputs <- c(table5_file, harveststat_file)[
  !file.exists(c(table5_file, harveststat_file))
]

if (length(missing_inputs) > 0) {
  stop(
    "The following input file(s) could not be found:\n",
    paste0(" - ", missing_inputs, collapse = "\n"),
    "\nCheck that the filenames in the Sahvara folder match the script exactly.",
    call. = FALSE
  )
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# -----------------------------------------------------------------------------
# 2. Helper functions
# -----------------------------------------------------------------------------

# Table 5 contains entries such as "FCT (Nigeria)" and, occasionally, a missing
# closing parenthesis such as "Kogi (Nigeria". Remove the country suffix in both.
strip_country_suffix <- function(x) {
  x |>
    str_trim() |>
    str_remove("\\s*\\([^)]*\\)?\\s*$") |>
    str_trim()
}

make_key <- function(country, unit) paste(country, unit, sep = "||")

# -----------------------------------------------------------------------------
# 3. Read Table 5 and identify Sahvaran units
# -----------------------------------------------------------------------------

table5_raw <- read_excel(table5_file, sheet = table5_sheet)

table5 <- table5_raw |>
  transmute(
    country = as.character(.data[[names(table5_raw)[1]]]),
    table5_region = as.character(Region),
    table5_location = as.character(Location)
  ) |>
  filter(!is.na(country), !is.na(table5_region)) |>
  mutate(
    country = str_trim(country),
    unit = strip_country_suffix(table5_region),
    # Table 5 labels the NE5 observations "N32"; all non-CS4 rows are NE5.
    group = if_else(str_trim(table5_location) == "CS4", "CS4", "NE5")
  ) |>
  select(country, unit, group)

# -----------------------------------------------------------------------------
# 4. Crosswalk Table 5 names to HarvestStat admin-1 names
# -----------------------------------------------------------------------------

# HarvestStat v1.2 has no records for Cote d'Ivoire.
country_crosswalk <- tribble(
  ~country,          ~hv_country,
  "Nigeria",         "Nigeria",
  "Mauritania",      "Mauritania",
  "Burkina Faso",    "Burkina Faso",
  "Cote d'Ivoire",   NA_character_,
  "Mali",            "Mali",
  "Ghana",           "Ghana",
  "Niger",           "Niger",
  "Togo",            "Togo",
  "Benin",           "Benin"
)

# Only names that differ between Table 5 and HarvestStat need to appear here.
admin_crosswalk <- tribble(
  ~country,        ~unit,                       ~hv_admin_override,
  "Nigeria",       "FCT",                       "Federal Capital Territory",
  "Mauritania",    "Tiris Zemmour & Inchiri",   "Inchiri",
  "Mauritania",    "Hosh el Gharbi",            "Hodh el Gharbi",
  "Mauritania",    "Hosh ech Chargui",          "Hodh ech Chargui",
  "Burkina Faso",  "Plateau Central",           "Plateau-Central",
  "Mali",          "Ségou",                     "Segou",
  "Mali",          "Timbuktu",                  "Tombouctou"
)

# These classifications reproduce the highlighting used in the figure.
administrative_capitals <- c(
  make_key("Nigeria", "FCT"),
  make_key("Burkina Faso", "Centre"),
  make_key("Cote d'Ivoire", "Yamoussoukro"),
  make_key("Mali", "Bamako"),
  make_key("Niger", "Niamey"),
  make_key("Mauritania", "Nouakchott Ouest"),
  make_key("Mauritania", "Nouakchott Nord"),
  make_key("Mauritania", "Nouakchott Sud")
)

commercial_capitals <- c(
  make_key("Nigeria", "Kaduna"),
  make_key("Nigeria", "Kano"),
  make_key("Ghana", "Northern"),
  make_key("Togo", "Kara"),
  make_key("Benin", "Borgou"),
  make_key("Niger", "Maradi")
)

hv <- read_csv(harveststat_file, show_col_types = FALSE)

available_admin1 <- hv |>
  distinct(country, admin_1) |>
  rename(hv_country = country, proposed_hv_admin_1 = admin_1) |>
  mutate(admin_exists = TRUE)

mapping <- table5 |>
  left_join(country_crosswalk, by = "country") |>
  left_join(admin_crosswalk, by = c("country", "unit")) |>
  mutate(
    proposed_hv_admin_1 = if_else(
      is.na(hv_country), NA_character_,
      coalesce(hv_admin_override, unit)
    ),
    unit_key = make_key(country, unit),
    capital_type = case_when(
      unit_key %in% administrative_capitals ~ "Administrative capital",
      unit_key %in% commercial_capitals ~ "Commercial capital",
      TRUE ~ "Not a capital"
    )
  ) |>
  left_join(available_admin1, by = c("hv_country", "proposed_hv_admin_1")) |>
  mutate(
    hv_admin_1 = if_else(admin_exists %in% TRUE, proposed_hv_admin_1, NA_character_),
    match_status = case_when(
      is.na(hv_country) ~ "No country coverage in HarvestStat",
      is.na(hv_admin_1) ~ "No matching admin-1 yield records",
      country == "Mauritania" & unit == "Tiris Zemmour & Inchiri" ~
        "Partial match: Inchiri only",
      unit == hv_admin_1 ~ "Exact match",
      TRUE ~ "Normalized name match"
    )
  ) |>
  select(country, unit, group, capital_type, hv_country, hv_admin_1, match_status)

# -----------------------------------------------------------------------------
# 5. Clean HarvestStat and retain each matched unit's latest five years
# -----------------------------------------------------------------------------

# Keep normal records (qc_flag 0) and low-variance warnings (qc_flag 2), while
# excluding records explicitly marked as outliers (qc_flag 1).
hv_clean <- hv |>
  filter(
    qc_flag != 1,
    !is.na(area), area > 0,
    !is.na(production),
    !is.na(harvest_year)
  )

matched_data <- mapping |>
  filter(!is.na(hv_admin_1)) |>
  inner_join(
    hv_clean,
    by = c("hv_country" = "country", "hv_admin_1" = "admin_1"),
    relationship = "many-to-many"
  )

# The five years are the latest five years available for the unit across all
# crops. They need not be consecutive.
latest_years <- matched_data |>
  distinct(country, unit, harvest_year) |>
  group_by(country, unit) |>
  arrange(desc(harvest_year), .by_group = TRUE) |>
  slice_head(n = n_recent_years) |>
  ungroup()

observations <- matched_data |>
  semi_join(latest_years, by = c("country", "unit", "harvest_year")) |>
  group_by(
    country, unit, hv_admin_1, group, capital_type, product, harvest_year
  ) |>
  summarise(
    area_ha = sum(area, na.rm = TRUE),
    production_mt = sum(production, na.rm = TRUE),
    source_rows = n(),
    .groups = "drop"
  ) |>
  group_by(country, unit) |>
  mutate(
    window_start = min(harvest_year),
    window_end = max(harvest_year)
  ) |>
  ungroup() |>
  mutate(yield_mt_ha = production_mt / area_ha)

# -----------------------------------------------------------------------------
# 6. Select the five crops with the greatest Sahvara-wide harvested acreage
# -----------------------------------------------------------------------------

unit_year_counts <- observations |>
  distinct(country, unit, harvest_year) |>
  count(country, unit, name = "window_years")

crop_ranking <- observations |>
  group_by(country, unit, product) |>
  summarise(area_ha = sum(area_ha), .groups = "drop") |>
  left_join(unit_year_counts, by = c("country", "unit")) |>
  mutate(avg_annual_area_ha = area_ha / window_years) |>
  group_by(product) |>
  summarise(
    sahvara_avg_annual_area_ha = sum(avg_annual_area_ha),
    units_reporting = n_distinct(unit),
    .groups = "drop"
  ) |>
  arrange(desc(sahvara_avg_annual_area_ha), product) |>
  mutate(rank = row_number())

top_crops <- crop_ranking |>
  slice_head(n = n_crops) |>
  pull(product)

message("Selected crops: ", paste(top_crops, collapse = ", "))

# -----------------------------------------------------------------------------
# 7. Calculate acreage-weighted yield and rank units from low to high
# -----------------------------------------------------------------------------

# This is a ratio of sums, not an unweighted average of reported yield values:
#     average yield = total production / total harvested area.
yield_summary <- observations |>
  filter(product %in% top_crops) |>
  group_by(country, unit, group, capital_type) |>
  summarise(
    selected_area_ha = sum(area_ha),
    selected_production_mt = sum(production_mt),
    crops_reporting = n_distinct(product),
    first_year = min(harvest_year),
    last_year = max(harvest_year),
    .groups = "drop"
  ) |>
  mutate(avg_yield_mt_ha = selected_production_mt / selected_area_ha) |>
  arrange(avg_yield_mt_ha, unit) |>
  mutate(rank_low_to_high = row_number())

results_all_units <- mapping |>
  left_join(
    yield_summary,
    by = c("country", "unit", "group", "capital_type")
  ) |>
  mutate(included_in_chart = !is.na(avg_yield_mt_ha))

# -----------------------------------------------------------------------------
# 8. Produce the ranked publication chart
# -----------------------------------------------------------------------------

country_codes <- c(
  "Nigeria" = "NG", "Mauritania" = "MR", "Burkina Faso" = "BF",
  "Mali" = "ML", "Ghana" = "GH", "Niger" = "NE", "Togo" = "TG",
  "Benin" = "BJ"
)

plot_data <- yield_summary |>
  mutate(
    coverage_mark = if_else(crops_reporting < n_crops, "†", ""),
    partial_mark = if_else(unit == "Tiris Zemmour & Inchiri", "‡", ""),
    plot_label = paste0(
      unit, " (", unname(country_codes[country]), ")",
      coverage_mark, partial_mark
    ),
    highlight = case_when(
      capital_type == "Administrative capital" ~ "Administrative capital",
      capital_type == "Commercial capital" ~ "Commercial capital",
      group == "CS4" ~ "CS4",
      TRUE ~ "NE5"
    ),
    plot_label = factor(plot_label, levels = plot_label)
  )

fill_values <- c(
  "CS4" = "#E31A1C",
  "NE5" = "#1F78B4",
  "Administrative capital" = "#FFD92F",
  "Commercial capital" = "#FFD92F"
)

line_values <- c(
  "CS4" = "solid",
  "NE5" = "solid",
  "Administrative capital" = "solid",
  "Commercial capital" = "dotted"
)

outline_values <- c(
  "CS4" = "#E31A1C",
  "NE5" = "#1F78B4",
  "Administrative capital" = "#202020",
  "Commercial capital" = "#202020"
)

chart_note <- paste0(
  "Basket: ", paste(top_crops, collapse = ", "),
  ".  † Fewer than all five basket crops reported.  ",
  "‡ Partial geographic match (Inchiri only).  ",
  sum(is.na(results_all_units$avg_yield_mt_ha)),
  " Table 5 units lack matched yield data and are excluded.\n",
  "Source: Author's calculations from HarvestStat Africa v1.2 and Table 5 ",
  "(OPHI/UNDP 2024 compilation)."
)

p <- ggplot(
  plot_data,
  aes(
    x = plot_label,
    y = avg_yield_mt_ha,
    fill = highlight,
    colour = highlight,
    linetype = highlight
  )
) +
  geom_col(width = 0.82, linewidth = 0.55) +
  scale_fill_manual(values = fill_values, breaks = names(fill_values)) +
  scale_colour_manual(values = outline_values, breaks = names(fill_values)) +
  scale_linetype_manual(values = line_values, breaks = names(fill_values)) +
  scale_y_continuous(
    labels = label_number(accuracy = 0.1),
    expand = expansion(mult = c(0, 0.13))
  ) +
  labs(
    title = "Average yield of the Sahvara's five largest crops by harvested area",
    subtitle = paste0(
      "Acreage-weighted yield across each unit's latest ", n_recent_years,
      " available HarvestStat years; units ordered low to high"
    ),
    x = NULL,
    y = "Average yield (metric tonnes per hectare)",
    fill = NULL,
    colour = NULL,
    linetype = NULL,
    caption = chart_note
  ) +
  theme_minimal(base_family = "sans", base_size = 10) +
  theme(
    plot.title = element_text(size = 16, hjust = 0, face = "plain"),
    plot.subtitle = element_text(size = 10, colour = "#333333"),
    axis.text.x = element_text(angle = 68, hjust = 1, vjust = 1, size = 6.3),
    axis.text.y = element_text(size = 9),
    axis.title.y = element_text(size = 10),
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank(),
    panel.grid.major.y = element_line(colour = "#D4D4D4", linewidth = 0.4),
    legend.position = "top",
    legend.justification = "left",
    legend.box.just = "left",
    plot.caption = element_text(hjust = 0, size = 8, colour = "#333333"),
    plot.margin = margin(15, 15, 15, 15)
  ) +
  guides(
    fill = guide_legend(nrow = 1),
    colour = guide_legend(nrow = 1),
    linetype = guide_legend(nrow = 1)
  )

ggsave(
  filename = file.path(output_dir, "sahvara_average_agricultural_yield.png"),
  plot = p,
  width = 18,
  height = 10.5,
  units = "in",
  dpi = 400,
  bg = "white"
)

# -----------------------------------------------------------------------------
# 9. Save auditable outputs
# -----------------------------------------------------------------------------

write_csv(mapping, file.path(output_dir, "01_unit_mapping.csv"))
write_csv(crop_ranking, file.path(output_dir, "02_crop_ranking.csv"))
write_csv(observations, file.path(output_dir, "03_crop_year_observations.csv"))
write_csv(results_all_units, file.path(output_dir, "04_unit_yield_results.csv"))

write_xlsx(
  list(
    Methodology = tibble(
      item = c(
        "Crop-selection rule",
        "Selected crops",
        "Time window",
        "Yield calculation",
        "Quality-control rule"
      ),
      value = c(
        paste("Top", n_crops, "crops by summed average annual harvested area"),
        paste(top_crops, collapse = ", "),
        paste("Latest", n_recent_years, "available years within each unit"),
        "Sum of production divided by sum of harvested area",
        "Exclude qc_flag 1; retain qc_flag 0 and 2"
      )
    ),
    Mapping = mapping,
    Crop_Ranking = crop_ranking,
    Crop_Year_Data = observations,
    Results = results_all_units
  ),
  path = file.path(output_dir, "sahvara_yield_audit.xlsx")
)

message(
  "Finished. Charted ", nrow(yield_summary), " of ", nrow(mapping),
  " Table 5 units. Outputs are in: ", normalizePath(output_dir)
)
