## ----setUp---------------------------------------------------------------
library(tidyverse)

defaultParms <- list(rootDepthMax = 30, # Depth of the root zone in cm below surface
                     totalRootBiomass = 0.3, # Total Root Biomass, g/cm2
                     rootTurnover = 0.5,  # Below Ground Turnover Rate of roots, 1/yr
                     rootOmFrac = list(fast=0.8, slow=0.2), # root allocation to om pools (labile, slow), g/g
                     omDecayRate = list(fast=0.8, slow=0), # organic matter decay rate (labile, slow), 1/yr
                     ssc = 20, # Suspended Sediment Concentration, mg per liter
                     depthBelowMHW = 10) # Depth of Marsh Surface Below Mean High Water

defaultConsts <- list(soilLength = 1, soilWidth = 1, #assume a 1x1 cm2 area
                      shape='linear', #root weight distribution
                      packing = list(root = 0.085, #density of roots g-C/cm3
                                     organic = 0.085 ,  # Organic Self Packing Densities: k1 g-C/cm3
                                     mineral = 1.99), # Inorganic Self Packing Densities  k2 g-C/cm3
                      nTidesPerYear = 704, #number of high tides per year
                      sedimentInputType = c('constant', 'relative', 'dynamic')[1],
                      modernAge = NA) #max age in modern soil profile

## ----functionRootProfile-------------------------------------------------

#return the mass of the live roots between two layers
massLiveRoots <- function(layerBottom, layerTop, parms = defaultParms, consts = defaultConsts){
  
  if(!all(c('soilLength', 'soilWidth') %in% names(consts))){
    stop('Can not find all constants.')
  }
  soilLength <- consts$soilLength
  soilWidth <- consts$soilWidth
  
  if(!all(c('totalRootBiomass', 'rootDepthMax') %in% names(parms))){
    stop('Can not find all parameters.')
  }
  totalBiomassByArea <- parms$totalRootBiomass
  rootDepthMax <- parms$rootDepthMax
  
  totalRootMass <- soilLength*soilWidth*totalBiomassByArea
  
  ##reset the layers that are beyond the root inputs to have 0 depths
  layerBottom[layerBottom > rootDepthMax] <- rootDepthMax
  layerTop[layerTop > rootDepthMax] <- rootDepthMax
  
  if(consts$shape == 'linear'){
    #mass_per_depth = slope * depth + intercept
    #totalRootMass = 1/2 * rootDepthMax * intecept ==> intercept = 2 * totalRootMass / rootDepthMax
    #slope = - intercept/rootDepthMax
    #mass = integral(mass_per_depth, depth)
    rootMass <- 2*totalRootMass*(layerBottom-layerTop)/rootDepthMax - 
      totalRootMass *(layerBottom ^2-layerTop^2)/rootDepthMax^2
    return(rootMass)
  }else{
    stop('Unknown shape specified')
  }
}

##Check liveRoots
#massLiveRoots(layerBottom = seq(5, 40, by=5), layerTop=seq(0, 35, by=5))
#plot(massLiveRoots(layerBottom = seq(5, 40, by=5), layerTop=seq(0, 35, by=5)))
#sum(massLiveRoots(layerBottom = seq(1, 40, by=1), layerTop=seq(0, 39, by=1))) == defaultParms$totalRootBiomass


## ----functionFindVol-----------------------------------------------------
depthOfNotRootVolume <- function(nonRootVolume, parms = defaultParms, consts = defaultConsts){
 
  if(!all(c('soilLength', 'soilWidth', 'shape', 'packing') %in% names(consts))){
    stop('Can not find all constants.')
  }
  soilLength <- consts$soilLength
  soilWidth <- consts$soilWidth
  rootDensity <- consts$packing$root
  shape <- consts$shape
  
  if(!all(c('rootDepthMax', 'totalRootBiomass') %in% names(parms))){
    stop('Can not find all expected parameters.')
  }
  rootDepthMax <- parms$rootDepthMax
  totalBiomassByArea <- parms$totalRootBiomass
  
  ####
  totalRootMass <- soilLength*soilWidth*totalBiomassByArea
  totalRootVolume <- totalRootMass/rootDensity
  
  if(totalRootVolume > soilLength*soilWidth*rootDepthMax){
    stop('Bad root volume')
  }
  
  if(shape == 'linear'){
    rootWidth <- totalRootVolume*2/(rootDepthMax*soilLength)

    #nonRootVolume = ((rootWidth/rootDepthMax*depth^2)/2 + depth*(soilWidth-rootWidth))*soilLength
    #            0 = rootWidth / (2*rootDepthMax) * depth ^2 + 
    #                   (soilWidth-rootWidth) * depth - nonRootVolume/soilLength ##solve for depth
    coef1 <- rootWidth / (2*rootDepthMax)
    coef2 <- soilWidth-rootWidth
    coef3 <- -nonRootVolume/soilLength
    ansDepth <- (-coef2 + sqrt(coef2^2-4*coef1*coef3))/(2*coef1)
    
    #correct for beyond root zone
    behondRootZone <- nonRootVolume > soilLength*soilWidth*rootDepthMax - totalRootVolume
    ansDepth[behondRootZone] <- (rootDepthMax +
                            (nonRootVolume - soilLength*soilWidth*rootDepthMax + totalRootVolume ) /
                              (soilLength*soilWidth)) [behondRootZone] #treat as a square
    return(ansDepth)
  }else{
    stop('Unknown shape specified')
  }
}

##Check depth of non root volue
#tester <- depthOfNotRootVolume(nonRootVolume = 1:100)
#plot(tester)
##plot(tester[1:99] - tester[2:100])

## ----functionSedIn-------------------------------------------------------
sedimentInputs <- function(yrForward=NA, #time currently ignored
                           marshElevation = NA, #marshElevation
                           parms, consts){ 
  ##Check constants
  if(!all(c('nTidesPerYear', 'sedimentInputType') %in% names(consts))){
    stop('Can not find expected constant names')
  }
  inputType <- consts$sedimentInputType # c('constant', 'relative', 'dynamic')[1]
  
  if(!all(c('ssc') %in% names(parms))){
    stop('Can not find expected parameter names')
  }
  ssc <- parms$ssc # Suspended Sediment Concentration, mg per liter
  
  ##Pull the depth below mean high water
  depthBelowMHW <- NA
  if(inputType == 'constant' & ('depthBelowMHW' %in% names(parms))){
    depthBelowMHW <- parms$depthBelowMHW # Depth of Marsh Surface Below Mean High Water
  }else{
    if(!'meanHighWaterElevation' %in% names(consts)){
      stop('Missing meanHighWaterElevation from consts list')
    }
  }
  
  if(inputType == 'relative'){
    #print('relative')
    depthBelowMHW <- max(0, consts$meanHighWaterElevation - marshElevation)
  }
  
  if(inputType == 'dynamic' & all(is.finite(yrForward)) & is.function(consts$meanHighWaterElevation)){
    #print('dynamic')
    depthBelowMHW <- max(0, consts$meanHighWaterElevation(yrForward) - marshElevation)
  }
  
  if(is.na(depthBelowMHW)){
    stop('Bad depth below MHW defined.')
  }
 
  #print(depthBelowMHW)
  
  meanTidalHeight <- depthBelowMHW
  ssc_gPerCm2 <- ssc * 0.000001 # convert mg/l to grams/cm^2
  cumAnnWaterVol <- consts$nTidesPerYear * meanTidalHeight # Cumulative water volume
  annSediment <- ssc_gPerCm2 * cumAnnWaterVol #g-sediment per year
  
  return(annSediment)
}

#sedimentInputs(consts = defaultConsts, parms = defaultParms)

# constSealevel <- defaultConsts
# constSealevel$sedimentInputType <- c('constant', 'relative', 'dynamic')[2]
# constSealevel$modernAge <- 99
# constSealevel$meanHighWaterElevation <- 31.74 + defaultParms$depthBelowMHW
# sedimentInputs(marshElevation = 31.74, consts = constSealevel, parms = defaultParms)

# constRaising <- defaultConsts
# constRaising$sedimentInputType <- c('constant', 'relative', 'dynamic')[3]
# constRaising$modernAge <- max(startingProfile$age)
# constRaising$meanHighWaterElevation <- function(year){
#   return(31.74 + 0.03*year)
# }
# sedimentInputs(yrForward = 1, marshElevation = 31.74, consts = constRaising, parms = defaultParms)

## ----functionStepCohort--------------------------------------------------
nextCohort <- function(massPools=data.frame(age=0, fast_OM=0, slow_OM=0, mineral=0,
                                            layer_top=0, layer_bottom=0),
                       topInputs_gPerYr = sedimentInputs,
                       rootProfile_g = massLiveRoots,
                       parms,
                       consts, dt_yr=1 ){
  if(!all(c('age', 'fast_OM', 'slow_OM', 'mineral') %in% names(massPools))){
    stop('Badly named massPools')
  }
  
  if(!all(c( 'rootTurnover', 'rootOmFrac', 'omDecayRate') %in% names(parms))){
    stop('Can not find expected parameters.')
  }
  rootTurnover <- parms$rootTurnover
  rootOmFrac <- parms$rootOmFrac
  omDecayRate <- parms$omDecayRate
  
  if(!all(c('packing') %in% names(consts))){
    stop('Can not find expected constants.')
  }
  
  packing <- consts$packing
  
  if(!all(c('organic', 'mineral') %in% names(packing))){
    stop('Can not find expected packing densities.')
  }
  
  if(!all(c('fast', 'slow') %in% names(rootOmFrac))){
    stop('Can not find expected root fraction splits.')
  }
  
  if(!all(c('fast', 'slow') %in% names(omDecayRate))){
    stop('Can not find expected organic matter decay rates.')
  }
  
  #decay the OM pools and add dead roots
  ans <- massPools %>% 
    dplyr::select(age, fast_OM, slow_OM, mineral, layer_top, layer_bottom) %>%
    mutate(age = age + dt_yr,
           root_mass = rootProfile_g(layerTop = layer_top, layerBottom = layer_bottom,
                                     parms = parms,
                                     consts = consts)) %>%
    mutate(fast_OM = fast_OM + 
             root_mass * rootOmFrac$fast * rootTurnover * dt_yr -
             fast_OM * omDecayRate$fast * dt_yr,
           slow_OM = slow_OM + 
             root_mass * rootOmFrac$slow * rootTurnover * dt_yr -
             slow_OM * omDecayRate$slow * dt_yr)
  
  
  ans <- bind_rows(data.frame(age = 0, fast_OM= 0, slow_OM = 0, 
                              mineral = topInputs_gPerYr(yrForward = max(massPools$age) - consts$modernAge,
                                marshElevation = max(massPools$layer_bottom),
                                                         parms = parms, 
                                                         consts = consts) * dt_yr),
                   ans) %>% #add sediments to the top
    arrange(age) %>% #make sure things are sorted by age
    #calculate cumulative volumne of each pool
    mutate(cumCohortVol = cumsum( (fast_OM + slow_OM)*packing$organic + mineral*packing$mineral )) %>%
  #calculate depth profile
    mutate(layer_bottom = depthOfNotRootVolume(nonRootVolume = cumCohortVol,
                                               parms = parms, consts = consts)) %>%
    mutate(layer_top = c(0, layer_bottom[-length(layer_bottom)]))
  
  return(ans)
}


## ----functionMEM---------------------------------------------------------

runToMEM <- function(cohortStep = nextCohort, parms, consts, 
                     maxAge = 200, relTol = 1e-6, absTol = 1e-8){
  cohortProfile <- cohortStep(parms = parms, consts = consts)[1,]
  
  #record.ls <- list(cohortProfile)
  for(ii in 2:maxAge){
    #if(ii %% 10 == 0){
    #  record.ls[[sprintf('Yr%d', ii)]] <- cohortProfile
    #}
    #oldCohort <- cohortProfile
    cohortProfile <- cohortStep(massPools = cohortProfile,
                                parms = parms,
                                consts = consts)
    
    ##have the last layer OM pools stabilized?
    if(abs(diff(cohortProfile$fast_OM[ii-c(0,1)] + cohortProfile$slow_OM[ii-c(0,1)])) < absTol |
       abs(diff(cohortProfile$fast_OM[ii-c(0,1)] + cohortProfile$slow_OM[ii-c(0,1)] ) /
           (cohortProfile$fast_OM[ii] + cohortProfile$slow_OM[ii])) < relTol){
      break
    }
  }
  return(cohortProfile)
}

## ----runMEM--------------------------------------------------------------

tick <- Sys.time()
equProfile <- runToMEM(consts = defaultConsts, parms=defaultParms)
tock <- Sys.time() - tick
print(tock)

ggplot(equProfile %>%
         gather(key='variable', value='value', -layer_top, -layer_bottom)) +
  geom_line(aes(x=(layer_top+layer_bottom)/2, y=value)) +
  facet_wrap(~variable, scales='free')

ggplot(equProfile) +
  geom_line(aes(x=(layer_top+layer_bottom)/2, y=layer_bottom - layer_top))


## ----convertToUnifDepth--------------------------------------------------
sampleStep<- 5
profile_by_depth <- data.frame(top = seq(0, floor(max(equProfile$layer_top) - sampleStep),
                                         by=sampleStep), 
           bottom = seq(sampleStep, floor(max(equProfile$layer_top)), by=sampleStep)) %>%
  group_by(top, bottom) %>%
  mutate(age = weighted.mean(equProfile$age, 
                             pmax(pmin(equProfile$layer_bottom, bottom) - 
                                    pmax(equProfile$layer_top, top), 0)),
         fast_OM = sum(equProfile$fast_OM *
                             pmax(pmin(equProfile$layer_bottom, bottom) - 
                                    pmax(equProfile$layer_top, top), 0) / 
                         (equProfile$layer_bottom - equProfile$layer_top)),
         slow_OM = sum(equProfile$slow_OM * 
                             pmax(pmin(equProfile$layer_bottom, bottom) - 
                                    pmax(equProfile$layer_top, top), 0) / 
                         (equProfile$layer_bottom - equProfile$layer_top)),
         mineral = sum(equProfile$mineral* 
                             pmax(pmin(equProfile$layer_bottom, bottom) - 
                                    pmax(equProfile$layer_top, top), 0) / 
                         (equProfile$layer_bottom - equProfile$layer_top)),
         root = sum(equProfile$root_mass * 
                             pmax(pmin(equProfile$layer_bottom, bottom) - 
                                    pmax(equProfile$layer_top, top), 0) / 
                         (equProfile$layer_bottom - equProfile$layer_top)),
         soil_volume = sum((equProfile$cumCohortVol - 
                        c(0, equProfile$cumCohortVol[-length(equProfile$cumCohortVol)])) * 
                             pmax(pmin(equProfile$layer_bottom, bottom) - 
                                    pmax(equProfile$layer_top, top), 0) / 
                         (equProfile$layer_bottom - equProfile$layer_top))) %>%
  mutate(bulk_density = sum(fast_OM+slow_OM+mineral)/soil_volume) %>%
  mutate(SOM = sum(fast_OM+slow_OM)/bulk_density)

ggplot(profile_by_depth) +
  geom_line(aes(x=(top+bottom)/2, y=age)) +
  geom_line(data=equProfile, aes(x=(layer_top+layer_bottom)/2, y=age), color='yellow', linetype=3)

ggplot(profile_by_depth %>%
         gather(key='variable', value='value', SOM, bulk_density, fast_OM, slow_OM, mineral)) +
  geom_line(aes(x=(top+bottom)/2, y=value)) +
  facet_wrap(~variable, scales = 'free_y')

## ----parameterRuns-------------------------------------------------------
parametersToRun <- expand.grid(rootDepthMax=c(15, 30, 60), 
            totalRootBiomass=c(0.15, 0.3, 0.6),
            rootTurnover=c(0.25, 0.5, 0.9),
            rootOmFrac_fast=c(0.2, 0.4, 0.8),
            omDecayRate_fast=c(0.2, 0.4, 0.8),
            ssc=c(10, 20, 40),
            depthBelowMHW=c(5, 10, 20)) %>%
  filter(rootDepthMax*defaultConsts$packing$root/2 >
           totalRootBiomass) %>% #check that we don't have above a max biomass per area
  sample_n(size=60) %>%
  #slice(c(20, 14, 93, 400, 3000, 12000, 10000)) %>% # nrow = 12 600
  mutate(index = 1:n()) %>%
  group_by_all() %>%
  do((function(xx){
    newParms <- list(rootDepthMax = xx$rootDepthMax, # Depth of the root zone in cm below surface
                     totalRootBiomass = xx$totalRootBiomass, # Total Root Biomass, g/cm2
                     rootTurnover = xx$rootTurnover,  # Below Ground Turnover Rate of roots, 1/yr
                     rootOmFrac = list(fast=xx$rootOmFrac_fast, 
                                       slow=1-xx$rootOmFrac_fast), # root allocation to om pools (labile, slow), g/g
                     omDecayRate = list(fast=xx$omDecayRate_fast, slow=0), # organic matter decay rate (labile, slow), 1/yr
                     ssc = xx$ssc, # Suspended Sediment Concentration, mg per liter
                     depthBelowMHW = xx$depthBelowMHW)
    return(runToMEM(parms = newParms, consts = defaultConsts, maxAge=1000))
  })(.)) %>%
  mutate('Total OM [g]' = fast_OM + slow_OM,
         'Soil volume [cm3]' = (fast_OM + slow_OM) / defaultConsts$packing$organic +
                       mineral/defaultConsts$packing$mineral,
         'OM [g g-1]' = (fast_OM + slow_OM) / (fast_OM + slow_OM + mineral)) %>%
  mutate('SOM [g-OM cm-3]' = `Total OM [g]` / `Soil volume [cm3]`)


ggplot(parametersToRun %>%
         gather(key='variable', value='value', age:mineral, root_mass, `Total OM [g]`:`SOM [g-OM cm-3]`)) +
  geom_line(aes(x=(layer_top+layer_bottom)/2, y=value, group=index), alpha=0.3) +
  scale_y_log10() +
  facet_wrap(~variable, scales='free')

## ----steadySealevel------------------------------------------------------
steadySeaLevel <- equProfile

constSealevel <- defaultConsts
constSealevel$sedimentInputType <- c('constant', 'relative', 'dynamic')[2]
constSealevel$modernAge <- max(equProfile$age)
constSealevel$meanHighWaterElevation <- max(equProfile$layer_bottom) + defaultParms$depthBelowMHW

for(ii in 1:100){
  steadySeaLevel <- nextCohort(massPools = steadySeaLevel, 
                             parms=defaultParms, consts = constSealevel)  
}

print(sprintf('Change in marsh elevation %.4f cm',max(steadySeaLevel$layer_bottom) - max(equProfile$layer_bottom)))

ggplot(steadySeaLevel) +
  geom_line(aes(x=(layer_top+layer_bottom)/2, y=age)) +
  geom_line(data=equProfile, aes(x=(layer_top+layer_bottom)/2, y=age), color='grey')

ggplot(steadySeaLevel %>%
         gather(key='variable', value='value', fast_OM:mineral, root_mass)) +
  geom_line(aes(x=(layer_top+layer_bottom)/2,# - 
                  #max(layer_bottom) + max(startingProfile$layer_bottom),
                y=value/(layer_bottom-layer_top))) +
  geom_line( data = equProfile %>%
               gather(key='variable', value='value', fast_OM:mineral, root_mass),
         aes(x=(layer_top+layer_bottom)/2,
                y=value/(layer_bottom-layer_top)), color='grey') +
  facet_wrap(~variable, scales='free')

## ----rasingSealevel------------------------------------------------------
raisingSeaLevel <- equProfile

constRaising <- defaultConsts
constRaising$sedimentInputType <- c('constant', 'relative', 'dynamic')[3]
constRaising$modernAge <- max(equProfile$age)
constRaising$meanHighWaterElevation <- function(year){
  return(max(equProfile$layer_bottom) + 0.03*year)
}

for(ii in 1:100){
  raisingSeaLevel <- nextCohort(massPools = raisingSeaLevel, 
                             parms=defaultParms, consts = constRaising)  
}

print(sprintf('Change in marsh elevation %.4f cm',max(raisingSeaLevel$layer_bottom) - max(equProfile$layer_bottom)))

ggplot(raisingSeaLevel) +
  geom_line(aes(x=(layer_top+layer_bottom)/2, y=age)) +
  geom_line(data=equProfile, aes(x=(layer_top+layer_bottom)/2, y=age), color='grey')

ggplot(raisingSeaLevel %>%
         gather(key='variable', value='value', fast_OM:mineral, root_mass)) +
  geom_line(aes(x=(layer_top+layer_bottom)/2,# - 
                  #max(layer_bottom) + max(startingProfile$layer_bottom),
                y=value/(layer_bottom-layer_top))) +
  geom_line( data = equProfile %>%
               gather(key='variable', value='value', fast_OM:mineral, root_mass),
         aes(x=(layer_top+layer_bottom)/2,
                y=value/(layer_bottom-layer_top)), color='grey') +
  facet_wrap(~variable, scales='free')

