library(shiny)
library(here)
library(tidyverse)
library(readxl)
library(lubridate)
library(DT)
library(leaflet)
library(bslib)
library(gee)

# Load conflict datasets
## other data that we're not using yet
### gtd_2021 <- read_xlsx(here("data","GTD_2021Jan-June_1222dist.xlsx"))
### gtd_full <- read_xlsx(here("data","GTD_0522dist.xlsx"))
acled_raw <- read_csv(here("data","ACLED_Africa_Regions_1-1-1900--1-30-2025.csv"))

acled=acled_raw |>
  mutate(longitude = as.numeric(longitude),
         latitude = as.numeric(latitude)) %>%
  filter(!is.na(longitude), !is.na(latitude)) %>%
  mutate(event_date = dmy(event_date))  # Converts "24 January 2025" to Date format


# Fetch SPEI data from Google Earth Engine
get_spei_data <- function(region, start_date, end_date) {
  spei <- ee$ImageCollection("SPEI/SPEI_02")$
    filterBounds(region)$
    filterDate(start_date, end_date)$
    mean()
  
  # Reduce the image collection to a numerical value over the region
  spei_values <- spei$reduceRegion(
    reducer = ee$Reducer$mean(),
    geometry = region,
    scale = 5000
  )$getInfo()
  
  return(spei_values)
}




# Define UI
ui <- fluidPage(
  theme = bs_theme(
    bg = "#f4f4f4", fg = "#222222", primary = "#005f73",
    base_font = font_google("Lato"), heading_font = font_google("Merriweather")
  ),
  titlePanel(div(style = "color:#005f73; font-size: 24px;", "Sub-Saharan Africa Conflict & Climate Analysis")),
  sidebarLayout(
    sidebarPanel(
      selectInput("country", "Select Country:", choices = NULL),
      sliderInput("year", "Select Year:", min = 2000, max = 2025, value = c(2010, 2025), sep = ""),
      selectInput("event_type", "Select Event Type:", choices = NULL, multiple = TRUE),
      actionButton("update", "Update Data", class = "btn-primary")
    ),
    mainPanel(
      tabsetPanel(
        tabPanel("Overview",
                 h3("Project Purpose", style = "color:#005f73;"),
                 p("This Shiny app analyzes patterns of armed conflict and terrorism across Sub-Saharan Africa in relation to climate conditions.", style = "font-size:16px;"),
                 img(src = "example_image.jpg", height = "300px")),
        tabPanel("Conflict Map",
                 leafletOutput("conflictMap", height = 500)),
        tabPanel("Data Summary",
                 DTOutput("dataTable")),
        tabPanel("Climate Trends",
                 plotOutput("climatePlot")),
        tabPanel("Advanced Analysis",
                 plotOutput("analysisPlot"),
                 p("This section applies an advanced data analysis technique to uncover patterns in the data."))
      )
    )
  )
)

# Define Server
server <- function(input, output, session) {
  # Populate country dropdown dynamically
  observe({
    updateSelectInput(session, "country", choices = sort(unique(acled$country)))
  })
  
  # Populate event type dropdown dynamically
  observe({
    updateSelectInput(session, "event_type", choices = unique(acled$event_type))
  })
  
  # Reactive dataset based on user inputs
  filtered_data <- reactive({
    req(input$country)
    acled %>%
      filter(year(event_date) >= input$year[1],
             year(event_date) <= input$year[2],
             country == input$country,
             event_type %in% input$event_type)
  })
  
  # Fetch and render SPEI data
  spei_data <- reactive({
    req(input$country, input$year)
    country_geom <- ee$FeatureCollection("FAO/GAUL/2015/level0")$
      filter(ee$Filter$eq("ADM0_NAME", input$country))
    get_spei_data(country_geom, paste0(input$year[1], "-01-01"), paste0(input$year[2], "-12-31"))
  })
  
  output$climatePlot <- renderPlot({
    spei_values <- spei_data()
    if (is.null(spei_values)) return(NULL)
    
    df <- tibble(
      Year = seq(input$year[1], input$year[2]),
      SPEI = rep(spei_values[[1]], length.out = length(seq(input$year[1], input$year[2])))
    )
    
    ggplot(df, aes(x = Year, y = SPEI)) +
      geom_line(color = "#005f73", size = 1) +
      labs(title = "SPEI Climate Trends", x = "Year", y = "SPEI Index") +
      theme_minimal()
  })
  
  
  # Render Leaflet map
  output$conflictMap <- renderLeaflet({
    req(nrow(filtered_data()) > 0)
    
    leaflet(filtered_data()) %>%
      addTiles() %>%
      addCircleMarkers(
        lng = ~longitude, lat = ~latitude,
        color = "red",
        radius = ~ifelse(fatalities > 0, sqrt(fatalities) * 2, 3),  # Scale size, min size 3
        popup = ~paste0(
          "<b>Event Type:</b> ", event_type, "<br>",
          "<b>Event Date:</b> ", event_date,"<br>",
          "<b>Actor:</b> ", actor1, "<br>",
          "<b>Fatalities:</b> ", fatalities, "<br>",
          "<b>Notes:</b> ", notes
        )
      )
  })
  
  # Render data table
  output$dataTable <- renderDT({
    datatable(filtered_data(), options = list(pageLength = 10, autoWidth = TRUE))
  })
  
  # Render Advanced Analysis plot
  output$analysisPlot <- renderPlot({
    ggplot(filtered_data(), aes(x = longitude, y = latitude, color = event_type)) +
      geom_point(alpha = 0.7) +
      labs(title = "Spatial Distribution of Conflict Events", x = "Longitude", y = "Latitude") +
      theme_minimal()
  })
}

# Run App
shinyApp(ui, server)

