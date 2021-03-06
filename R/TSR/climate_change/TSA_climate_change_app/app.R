# Copyright 2018 Province of British Columbia
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and limitations under the License.

library (shiny)
library (shinythemes)
require (RPostgreSQL)
require (sf)
require (raster)
require (rpostgis)
require (dplyr)
require (leaflet)
require (leaflet.extras)

#===================================================================================
# Functions for retrieving data from the postgres server (vector, raster and tables)
#==================================================================================
getSpatialQuery <- function (sql) {
  conn <- dbConnect (dbDriver("PostgreSQL"), 
                     host = "",
                     user = "postgres",
                     dbname = "postgres",
                     password = "postgres",
                     port = "5432")
  on.exit (dbDisconnect (conn))
  st_read (conn, query = sql)
}

getTableQuery<-function(sql){
  conn <- dbConnect (dbDriver("PostgreSQL"), 
                     host = "",
                     user = "postgres",
                     dbname = "postgres",
                     password = "postgres",
                     port = "5432")
  on.exit (dbDisconnect (conn))
  dbGetQuery (conn, sql)
}

#======================
# Spatial data objects
#=====================
tsa.diss <- getSpatialQuery ("SELECT * FROM fadm_tsa_dissolve_polygons")
map.tsa.diss <- sf::as_Spatial (st_transform (tsa.diss, 4326))
bec <- getTableQuery ("SELECT * FROM public.plot_data_bec")

# Define UI for application that draws a histogram
ui <- fluidPage (theme = shinytheme ("superhero"), 
   
   # Application title and description
   titlePanel ("Timber Supply Area Climate Change Summaries in British Columbia"),
   tags$p ("This application allows you to explore how some climate variables are predicted to change in timber supply areas in British Columbia. "),
   tags$p (HTML (paste0 ("All climate data was downloaded from the climate BC website ", a (href = 'http://climatebcdata.climatewna.com/#3._reference', 'Wang et al. 2012'),"."))),
   
   # Sidebar  
   sidebarLayout(
      sidebarPanel (
        helpText ("Click map to select a timber supply area"), # text size?
        # TSA name
        h2 (textOutput ("clickTSA")),
        helpText ("Timber supply area"),
        selectInput (inputId = "climateVar",
                     label = "Choose a climate variable:",
                     choices = c ("Annual Heat Moisture Index", "Degree Days Above 5C", 
                                  "Degree Days below 0C", "Extreme Maximum Temperature Over 30 Years",
                                  "Extreme Minimum Temperature Over 30 Years", 
                                  "Mean Annual Precipitation (mm)", "Mean Annual Temperature (C)",
                                  "Mean Coldest Month Temperature (C)", 
                                  "Mean May to September Precipitation (mm)", 
                                  "Mean Warmest Month Temperature (C)", "Number of Frost Free Days",
                                  "Precipitation as Snow August to July", "Relative Humidity"),
                     selected = "Mean Annual Temperature (C)"
        ) # closes selectinput
      ), # closes sidebarPanel
      
      # Show a plot of the generated distribution
      mainPanel(
        leafletOutput ("map"),
        tabsetPanel(
          tabPanel("Biogeoclimatic Ecosystem Classification Plot",  
                    plotOutput (outputId = "becTSAPlot", height = "300px")),
          tabPanel("Climate Variable Plot", 
                  plotOutput (outputId = "climateVarTSAPlot", height = "300px"))
          
        ) # closes tabsetpanels
      ) # closes mainpanel
   ) # closes sidebarlayout
) # closes fluidpage

# Define server logic required to draw a histogram
server <- function (input, output) {
   
   # select the TSA
   TSASelect <- reactive ({
                  tsa.diss[tsa.diss$TSA_NUMB_1 == input$map_shape_click$group, ]
   })
  
   # reactive values
   TSA <- reactive ({
            as.character(input$map_shape_click$group)
   })
 
   becData <- reactive({
     dplyr::filter (bec, tsa == TSA ())
   })
   
   # render the leaflet map  
   output$map = renderLeaflet ({ 
     leaflet (map.tsa.diss, options = leafletOptions (doubleClickZoom = TRUE)) %>% 
       setView (-121.7476, 53.7267, 4) %>%
       addTiles() %>% 
       addProviderTiles ("OpenStreetMap", group = "OpenStreetMap") %>%
       addProviderTiles ("Esri.WorldImagery", group ="WorldImagery" ) %>%
       addProviderTiles ("Esri.DeLorme", group = "DeLorme" ) %>%
       addPolygons (data = map.tsa.diss,  
                    stroke = T, weight = 1, opacity = 1, color = "blue", 
                    dashArray = "2 1", fillOpacity = 0.5,
                    smoothFactor = 0.5,
                    layerId = ~TSA_NUMB_1,
                    group = ~TSA_NUMB_1,
                    label = ~TSA_NUMB_1,
                    labelOptions = labelOptions (noHide = FALSE, textOnly = TRUE, opacity = 1, 
                                                 color= "black", textsize='15px'),
                    highlight = highlightOptions (weight = 4, color = "white", dashArray = "", 
                                                  fillOpacity = 0.3, bringToFront = TRUE)) %>%
       addScaleBar (position = "bottomright") %>%
       addControl (actionButton ("reset", "Refresh", icon = icon("refresh"), 
                                  style = "background-position: -31px -2px;"),
                   position="bottomleft") %>%
       addDrawToolbar (
         editOptions = editToolbarOptions (),
         targetGroup='Drawn',
         circleOptions = FALSE,
         circleMarkerOptions = FALSE,
         rectangleOptions = FALSE,
         markerOptions = FALSE,
         singleFeature = F,
         polygonOptions = drawPolygonOptions (showArea = TRUE, 
                                              shapeOptions = drawShapeOptions (fillOpacity = 0,
                                                                               color = 'red',
                                                                               weight = 3, 
                                                                               clickable = TRUE))) %>%
       addLayersControl (baseGroups = c ("OpenStreetMap", "WorldImagery", "DeLorme"), 
                         options = layersControlOptions (collapsed = TRUE))
    })
   
   # Observe the selection of the TSA 
   observeEvent(input$map_shape_click, {
     output$clickTSA <- renderText (TSA ())
   })
   
   ## Zoom to TSA being clicked
   observe({
     if (is.null (input$map_shape_click))
       return ()
     
     leafletProxy ("map") %>%
       clearShapes () %>%
       clearControls () %>%
       setView (lng = input$map_shape_click$lng,lat = input$map_shape_click$lat, zoom = 6) %>%
       addPolygons (data = as_Spatial (st_transform (TSASelect(), 4326)), 
                    fillOpacity = 0.1, color = "red", weight = 4,
                    labelOptions = labelOptions (noHide = FALSE, textOnly = TRUE, opacity = 0.5, 
                                                 textsize = '13px'),
                   options = pathOptions (clickable = FALSE)) %>%
       addControl (actionButton ("reset", "Refresh", icon = icon("refresh"), 
                                 style = "background-position: -31px -2px;"),
                                 position = "bottomleft") %>%
       addScaleBar (position = "bottomright") %>%
       addDrawToolbar(
         editOptions = editToolbarOptions(),
         targetGroup='Drawn',
         circleOptions = FALSE,
         circleMarkerOptions = FALSE,
         rectangleOptions = FALSE,
         markerOptions = FALSE,
         singleFeature = F,
         polygonOptions = drawPolygonOptions (showArea = TRUE, 
                                              shapeOptions = drawShapeOptions (fillOpacity = 0,
                                                                               color = 'red',
                                                                               weight = 3, 
                                                                               clickable = TRUE))) %>%
       addLayersControl (baseGroups = c("OpenStreetMap","WorldImagery", "DeLorme"),
                         options = layersControlOptions(collapsed = TRUE))
   })
   
   
   ## reset map
   observeEvent(input$reset, {
     leafletProxy ("map") %>%
       clearShapes () %>%
       clearControls () %>%
       setView (-121.7476, 53.7267, 4) %>%
       addControl (actionButton ("reset","Refresh", icon = icon ("refresh"), 
                                 style = "background-position: -31px -2px;"), 
                                 position = "bottomleft") %>%
       addPolygons (data = map.tsa.diss,  
                    stroke = T, weight = 1, opacity = 1, color = "blue", 
                    dashArray = "2 1", fillOpacity = 0.5,
                    smoothFactor = 0.5,
                    layerId = ~TSA_NUMB_1,
                    group = ~TSA_NUMB_1,
                    label = ~TSA_NUMB_1,
                    labelOptions = labelOptions (noHide = FALSE, textOnly = TRUE, opacity = 1, 
                                                 color= "black", textsize='15px'),
                    highlight = highlightOptions (weight = 4, color = "white", dashArray = "", 
                                                  fillOpacity = 0.3, bringToFront = TRUE)) %>%
       addLayersControl (baseGroups = c ("OpenStreetMap", "WorldImagery", "DeLorme"), 
                         options = layersControlOptions (collapsed = TRUE))
   })
   
   
   # bec plot
   output$becTSAPlot <- renderPlot({
     
     ggplot (becData (), 
             aes (x = year)) +  
       geom_bar (aes (fill = bec), position = 'fill') +
       ggtitle (paste (TSA ())) +
       xlab ("Year") +
       ylab ("Proportion of range area") +
       scale_fill_discrete (name = "BEC Zone") +
       theme (axis.text = element_text (size = 12),
              axis.title =  element_text (size = 14, face = "bold"))

   })
   
   # climate variable plots
   output$climateVarTSAPlot <- renderPlot({
   })
   
}

# Run the application 
shinyApp(ui = ui, server = server)

