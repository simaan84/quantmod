require(quantmod)
require(lubridate)
require(plyr)

rm(list = ls())

{
  `getOptionChain` <-
    function(Symbols, Exp=NULL, src="yahoo", ...) {
      Call <- paste("getOptionChain",src,sep=".")
      if(missing(Exp)) {
        do.call(Call, list(Symbols=Symbols, ...))
      } else {
        do.call(Call, list(Symbols=Symbols, Exp=Exp, ...))
      }
    }
  
  getOptionChain.yahoo <- function(Symbols, Exp, ...)
  {
    if(!requireNamespace("jsonlite", quietly=TRUE))
      stop("package:",dQuote("jsonlite"),"cannot be loaded.")
    
    NewToOld <- function(x) {
      if(is.null(x) || length(x) < 1)
        return(NULL)
      # clean up colnames, in case there's weirdness in the JSON
      names(x) <- tolower(gsub("[[:space:]]", "", names(x)))
      # set cleaned up colnames to current output colnames
      d <- with(x, data.frame(Strike=strike, Last=lastprice, Chg=change,
                              Bid=bid, Ask=ask, Vol=volume, OI=openinterest,
                              row.names=contractsymbol, stringsAsFactors=FALSE))
      
      # remove commas from the numeric data
      d[] <- lapply(d, gsub, pattern=",", replacement="", fixed=TRUE)
      d[] <- lapply(d, type.convert, as.is=TRUE)
      d
    }
    
    # Don't check the expiry date if we're looping over dates we just scraped
    checkExp <- !hasArg(".expiry.known") || !match.call(expand.dots=TRUE)$.expiry.known
    # Construct URL
    urlExp <- paste0("https://query2.finance.yahoo.com/v7/finance/options/", Symbols[1])
    # Add expiry date to URL
    if(!checkExp)
      urlExp <- paste0(urlExp, "?&date=", Exp)
    
    # Fetch data (jsonlite::fromJSON will handle connection)
    tbl <- jsonlite::fromJSON(urlExp)
    
    # Only return nearest expiry (default served by Yahoo Finance), unless the user specified Exp
    if(!missing(Exp) && checkExp) {
      all.expiries <- tbl$optionChain$result$expirationDates[[1]]
      all.expiries.posix <- .POSIXct(as.numeric(all.expiries), tz="UTC")
      
      # this is a recursive command
      if(is.null(Exp)) {
        # Return all expiries if Exp = NULL
        out <- lapply(all.expiries, getOptionChain.yahoo, Symbols=Symbols, .expiry.known=TRUE)
        # Expiry format was "%b %Y", but that's not unique with weeklies. Change
        # format to "%b.%d.%Y" ("%Y-%m-%d wouldn't be good, since names should
        # start with a letter or dot--naming things is hard).
        return(setNames(out, format(all.expiries.posix, "%b.%d.%Y")))
      }     
      
      else {
        # Ensure data exist for user-provided expiry date(s)
        if(inherits(Exp, "Date"))
          valid.expiries <- as.Date(all.expiries.posix) %in% Exp
        else if(inherits(Exp, "POSIXt"))
          valid.expiries <- all.expiries.posix %in% Exp
        else if(is.character(Exp)) {
          expiry.range <- range(unlist(lapply(Exp, .parseISO8601, tz="UTC")))
          valid.expiries <- all.expiries.posix >= expiry.range[1] &
            all.expiries.posix <= expiry.range[2]
        }
        if(all(!valid.expiries))
          stop("Provided expiry date(s) not found. Available dates are: ",
               paste(as.Date(all.expiries.posix), collapse=", "))
        
        expiry.subset <- all.expiries[valid.expiries]
        if(length(expiry.subset) == 1)
          return(getOptionChain.yahoo(Symbols, expiry.subset, .expiry.known=TRUE))
        else {
          out <- lapply(expiry.subset, getOptionChain.yahoo, Symbols=Symbols, .expiry.known=TRUE)
          # See comment above regarding the output names
          return(setNames(out, format(all.expiries.posix[valid.expiries], "%b.%d.%Y")))
        }
      }
    }
    
    dftables <- lapply(tbl$optionChain$result$options[[1]][,c("calls","puts")], `[[`, 1L)
    #dftables <- mapply(NewToOld, x=dftables, SIMPLIFY=FALSE)
    
    
    fix_date <- function(x) {
      if(class(x) == "list") 
        return(NULL)
      x$expiration <- .POSIXct(as.numeric(x$expiration), tz="UTC")
      x$lastTradeDate <- .POSIXct(as.numeric(x$lastTradeDate), tz="UTC")
      x <- x[,sort(names(x))]
      return(x)
    }
    
    dftables <- lapply(dftables,fix_date)
    dftables <- dftables[!sapply(dftables,is.null)]
    dftables
  }
  
}


# EXAMPLE to get all expiration in a single data.frame object
get_option_data <- function(tic) {
  ds <- getOptionChain.yahoo(tic,NULL)
  ds <- lapply(ds, function(ds_i) lapply(1:length(ds_i), 
                                         function(i) data.frame(Type = names(ds_i)[i], ds_i[[i]]))  )
  ds <- lapply(ds, function(ds_i) do.call(plyr::rbind.fill,ds_i)  )
  ds <- do.call(plyr::rbind.fill,ds)
  
  ds$tic <- tic
  ds$Date <- date(ds$lastTradeDate )
  ds$Expiration <- date(ds$expiration)
  today_date <- as.character(today())
  today_date <- paste(strsplit(today_date,"-")[[1]],collapse = "_")
  
  ds$expiration <- date( ds$expiration)
  ds$lastTradeDate <- date(ds$lastTradeDate)
  ds$tau <- as.numeric(ds$expiration - ds$lastTradeDate)/252
  ds$mid <- (ds$ask + ds$bid)/2
  ds1 <- ds
  # add spot price
  S <- get(getSymbols(tic))[,6]
  ds2 <- data.frame(lastTradeDate = date(S), Spot = as.numeric(S))
  ds12 <- merge(ds1,ds2, by = c("lastTradeDate"))
  
  return(ds12)
}




