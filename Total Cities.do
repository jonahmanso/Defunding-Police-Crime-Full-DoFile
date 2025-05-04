set more off
capture log close
cap clear matrix
clear

cd "/Users/jonahmanso/Desktop/CrimePoliceData"
log using "CrimePoliceData.log", replace

*THIS CODE WAS USED TO IMPORT, CLEAN, AND ANALYZE MY THESIS DATA

import excel using ReshapedCities2, firstrow clear

drop if missing(Crime_Rate)


*GENERATE MONTH AND YEAR VARIABLES
gen month = .
replace month = 1 if strpos(Month_Year, "Ja") > 0
replace month = 2 if strpos(Month_Year, "Fe") > 0
replace month = 3 if strpos(Month_Year, "Marr") > 0
replace month = 4 if strpos(Month_Year, "Ap") > 0
replace month = 5 if strpos(Month_Year, "Mayy") > 0
replace month = 6 if strpos(Month_Year, "Junn") > 0
replace month = 7 if strpos(Month_Year, "Jull") > 0
replace month = 8 if strpos(Month_Year, "Au") > 0
replace month = 9 if strpos(Month_Year, "Se") > 0
replace month = 10 if strpos(Month_Year, "Oc") > 0
replace month = 11 if strpos(Month_Year, "No") > 0
replace month = 12 if strpos(Month_Year, "De") > 0

gen Year = .
replace Year = 2015 if strpos(Month_Year, "2015") > 0
replace Year = 2016 if strpos(Month_Year, "2016") > 0
replace Year = 2017 if strpos(Month_Year, "2017") > 0
replace Year = 2018 if strpos(Month_Year, "2018") > 0
replace Year = 2019 if strpos(Month_Year, "2019") > 0
replace Year = 2020 if strpos(Month_Year, "2020") > 0
replace Year = 2021 if strpos(Month_Year, "2021") > 0
replace Year = 2022 if strpos(Month_Year, "2022") > 0
replace Year = 2023 if strpos(Month_Year, "2023") > 0


*GENERATE VIOLENT CRIME DUMMY
replace CrimeType = trim(CrimeType)
gen Violent = .
replace Violent = 0 if (CrimeType == "Arson" | CrimeType == "Burglary" | CrimeType == "Larceny Theft" | CrimeType == "Motor Vehicle Theft")
replace Violent = 1 if (CrimeType == "Aggravated Assault" | CrimeType == "Homicide" | CrimeType == "Rape" | CrimeType == "Robbery")


*FIX SYNTAX FOR POLICE DEPARTMENT STRING VAR
gen newvar = regexr(PoliceDepartment, "Police Department.*", "")
drop PoliceDepartment
rename newvar PoliceDept
order PoliceDept


*IMPORT OFFICERS DATA 
merge m:m PoliceDept Year using "ReshapedOfficers.dta"
sort Year month PoliceDept CrimeType
drop _merge

replace PoliceDept = trim(PoliceDept)


*IMPORT DEMOGRAPHICS DATA 
merge m:1 PoliceDept Year using "UpdatedDemographicsCleaned.dta"
sort Year month PoliceDept CrimeType
drop if _merge == 1
drop _merge

merge m:1 PoliceDept Year using "UpdatedMedHHInc.dta"
sort Year month PoliceDept CrimeType
drop _merge

rename poverty Poverty
save Merged.dta, replace

*CREATE TREATMENT AND COMPARISON GROUPS FOR SIMPLE DID
gen Officers_2019 = Officers if Year == 2019
gen Officers_2021 = Officers if Year == 2021
collapse (max) Officers_2019 Officers_2021, by(PoliceDept)
gen PctChngOfficers = ((Officers_2021 - Officers_2019) / Officers_2019) * 100

gen Treatment = (PctChngOfficers <= 0)
keep if PctChngOfficers >= -2
keep PoliceDept PctChngOfficers Treatment
save MakeTreatment.dta, replace


*MERGE TREATMENT VARIABLES TO MASTER DATA
use Merged.dta
merge m:1 PoliceDept using "MakeTreatment.dta"
drop _merge
sort Year month PoliceDept CrimeType


*CREATE PRE AND POST VARIABLES
gen Post = .
replace Post = 0 if Year <= 2019
replace Post = 1 if Year >= 2021

*CREATE POST FOR SUMMARY STATS
gen P2 = .
replace P2 = 0 if Year == 2019
replace P2 = 1 if Year == 2021


*CREATE TREATMENT PRE, TREATMENT POST, COMPARISON PRE, COMPARISON POST
gen Group = .
replace Group = 1 if Treatment == 1 & Post == 0
replace Group = 2 if Treatment == 1 & Post == 1
replace Group = 3 if Treatment == 0 & Post == 0
replace Group = 4 if Treatment == 0 & Post == 1


*CREATE THE TIME VARIABLE FOR MONTH AND YEAR 
gen monthyear = .

forvalues y = 2015/2023 {
    forvalues m = 1/12 {
        local ym = `y'*100 + `m'
        replace monthyear = `ym' if month == `m' & Year == `y'
    }
}

save Merged2.dta, replace


*COLLAPSE THEN MERGE TO CREATE OVERALL CRIME RATES + MERGE VIOLENT AND PROPERTY CRIME RATES
collapse (sum) Crime_Rate, by(PoliceDept Year monthyear)
rename Crime_Rate OverallCrimeRate

save OverallCrimeRate.dta, replace 

use Merged2.dta
merge m:1 PoliceDept monthyear using "OverallCrimeRate.dta"
drop _merge 
merge m:1 PoliceDept monthyear using "ViolentCrimeRate.dta"
drop _merge 
merge m:1 PoliceDept monthyear using "PropertyCrimeRate.dta"
drop _merge 

/*GENERATE VARS FOR ANALYSES BELOW 
gen TreatPost = Treatment*Post 
egen PDID = group(PoliceDept)
bysort PoliceDept (Year): gen Officers_Lag = Officers[_n-1]


/*CREATE THE LIST OF CITIES TABLE 
keep if Year == 2019 | Year == 2021
collapse (mean) OverallCrimeRate Officers Treatment, by(PDID P2)
reshape wide OverallCrimeRate Officers Treatment, i(PDID) j(P2)

*/
		  
/*CREATE A SUMMARY STATISTICS TABLE 
collapse (mean) OverallCrimeRate ViolentCR PropertyCR Officers UnempRate MedHHInc Poverty White Black Treatment P2, by(PoliceDept Year monthyear)

local append "replace"
foreach t in 1 0 {
	foreach p in 0 1 {
		outsum OverallCrimeRate ViolentCR PropertyCR Officers UnempRate MedHHInc Poverty White Black if Treatment==`t'&P2==`p' using ///
		TableMeans2.xls, `append' bracket
		local append "append"
		
	}
}  
*/


/*CREATE THE BALANCE TEST
collapse (mean) OverallCrimeRate ViolentCR PropertyCR Treatment Officers Post UnempRate MedHHInc Poverty White Black PDID, by(PoliceDept Year)
gen TreatPost = Treatment*Post

foreach var in OverallCrimeRate ViolentCR PropertyCR Officers UnempRate MedHHInc Poverty White Black {
    reg `var' TreatPost i.Year i.PDID, robust  
    outreg2 using BalanceTest.xls, excel ///
        addstat(Observations, e(N), R-squared, e(r2))
}
*/


/*OLS GRAPH 
collapse (mean) OverallCrimeRate Officers_Lag UnempRate MedHHInc Poverty White Black (semean) se_OverallCrimeRate=OverallCrimeRate, by(PDID Year)
foreach var in OverallCrimeRate Officers_Lag {
	reg `var' UnempRate MedHHInc Poverty White Black i.Year i.PDID
	predict `var'R, resid
}

twoway (scatter OverallCrimeRateR Officers_LagR, mcolor(blue) msymbol(O)) ///
       (lfit OverallCrimeRateR Officers_LagR, lcolor(red) lwidth(medium)), ///
       xtitle("Residualized Number of Officers (per 1000 people) in Year Y-1") ///
       ytitle("Residualized Crimes Committed per 100,000 people per Month (Averaged by Year)") ///
       title("Crime Rate vs. Lagged Officers") ///
       legend(order(1 "Cities by Year" 2 "Fitted Line") col(1) region(lcolor(none)))


*/


/*DID AVERAGES GRAPH
collapse (mean) OverallCrimeRate (semean) se_OverallCrimeRate=OverallCrimeRate, by(Treatment Year)
gen upper= OverallCrimeRate+1.96*se_OverallCrimeRate
gen lower= OverallCrimeRate-1.96*se_OverallCrimeRate
 
gr twoway (line OverallCrimeRate Year if Treatment==1, lcolor(blue)) ///
          (line OverallCrimeRate Year if Treatment==0, lcolor(red)) ///
          (rcap upper lower Year if Treatment==1, lc(blue)) ///
          (rcap upper lower Year if Treatment==0, lc(red)), ///
          xline(2010, lp(dash)) ///
          ytitle("Crimes Committed per 100,000 people per Month (Averaged by Year)") ///
          title("Average Crime Rate by City Type", size(medium)) ///
          legend(order(1 "Treatment Cities" 2 "Comparison Cities") ///
                 col(1) region(lcolor(none)))

*/


/*DID COEFFICIENTS GRAPH: EVENT STUDY MODEL
collapse (mean) OverallCrimeRate Officers Treatment Post TreatPost UnempRate MedHHInc Poverty White Black, by(PDID Year) 

*generate year dummies
foreach y of numlist 2015/2023 {
    gen Year`y' = (Year == `y')
}

*generate interaction terms between treatment and year 
foreach y of numlist 2021/2023 {
    gen Treat_Year`y' = Treatment * Year`y'
}

foreach y of numlist 2015/2019 {
    gen Treat_Year`y' = Treatment * Year`y'
}
*write the regression 
reg OverallCrimeRate Treat_Year* Treatment UnempRate MedHHInc Poverty White Black i.Year, robust
gen coef = 0 
gen se = . 
foreach Year in 2015 2016 2017 2018 2019 2021 2022 2023 {
	replace coef = _b[Treat_Year`Year'] if Year==`Year'
	replace se = _se[Treat_Year`Year'] if Year==`Year'
}
egen tag = tag(Year)
keep if tag==1 
keep Year coef se

*graph the coefficients 
gen ci_upper = coef + 1.96 * se
gen ci_lower = coef - 1.96 * se

twoway (scatter coef Year, msize(vsmall) mcolor(blue)) ///
       (rcap ci_upper ci_lower Year, lcolor(blue)), ///
       xtitle("Year") ytitle("Estimated Effect on Overall Monthly Crimes per 100,000 people") ///
       title("Event Study: Effect of Police on Crime Over Time") ///
       legend(off) xline(2020, lcolor(red) lpattern(dash)) ///
       graphregion(color(white))

gen crime_coef = .
gen crime_se = .
foreach Year in 2015 2016 2017 2018 2019 2021 2022 2023 {
    replace crime_coef = _b[Treat_Year`Year'] if Year == `Year'
    replace crime_se = _se[Treat_Year`Year'] if Year == `Year'
}

*/


/*DID AVERAGES GRAPH: OFFICERS
collapse (mean) Officers (semean) se_Officers=Officers, by(Treatment Year)
gen upper= Officers+1.96*se_Officers
gen lower= Officers-1.96*se_Officers
 
gr twoway (line Officers Year if Treatment==1, lcolor(blue)) ///
          (line Officers Year if Treatment==0, lcolor(red)) ///
          (rcap upper lower Year if Treatment==1, lc(blue)) ///
          (rcap upper lower Year if Treatment==0, lc(red)), ///
          xline(2010, lp(dash)) ///
          ytitle("Number of Officers per 1000 people per Year") ///
          title("Average Officers by City Type", size(medium)) ///
          legend(order(1 "Treatment Cities" 2 "Comparison Cities") ///
                 col(1) region(lcolor(none)))

*/


/*DID COEFFICIENTS GRAPH FOR OFFICERS
collapse (mean) Officers Treatment Post TreatPost UnempRate MedHHInc Poverty White Black, by(PDID Year) 

*generate year dummies
foreach y of numlist 2015/2023 {
    gen Year`y' = (Year == `y')
}

*generate interaction terms between treatment and year 
foreach y of numlist 2021/2023 {
    gen Treat_Year`y' = Treatment * Year`y'
}

foreach y of numlist 2015/2019 {
    gen Treat_Year`y' = Treatment * Year`y'
}
*write the regression 
reg Officers Treat_Year* Treatment UnempRate MedHHInc Poverty White Black i.Year, robust
gen coef = 0 
gen se = . 
foreach Year in 2015 2016 2017 2018 2019 2021 2022 2023 {
	replace coef = _b[Treat_Year`Year'] if Year==`Year'
	replace se = _se[Treat_Year`Year'] if Year==`Year'
}
egen tag = tag(Year)
keep if tag==1 
keep Year coef se

*graph the coefficients 
gen ci_upper = coef + 1.96 * se
gen ci_lower = coef - 1.96 * se

twoway (scatter coef Year, msize(vsmall) mcolor(blue)) ///
       (rcap ci_upper ci_lower Year, lcolor(blue)), ///
       xtitle("Year") ytitle("Estimated Effect on Average Yearly Officers per 1000 People") ///
       title("Event Study: Effect of Treatment Status on Police Over Time") ///
       legend(off) xline(2020, lcolor(red) lpattern(dash)) ///
       graphregion(color(white))
	   
gen officer_coef = .
gen officer_se = .
foreach Year in 2015 2016 2017 2018 2019 2021 2022 2023 {
    replace officer_coef = _b[Treat_Year`Year'] if Year == `Year'
    replace officer_se = _se[Treat_Year`Year'] if Year == `Year'
}
	   
*/


/*CREATE MAIN OLS RESULTS TABLE 
collapse (mean) OverallCrimeRate ViolentCR PropertyCR Officers_Lag Treatment Post UnempRate MedHHInc Poverty White Black, by(PDID Year) 

* OLS no controls or fe 
reg OverallCrimeRate Officers_Lag, robust
outreg2 using OLSTable.xls, addstat(Observations, e(N), R-squared, e(r2)) replace 

* OLS with fe
reg OverallCrimeRate Officers_Lag i.Year i.PDID, robust
outreg2 using OLSTable.xls, addstat(Observations, e(N), R-squared, e(r2)) append

*OLS with controls and fe 
reg OverallCrimeRate Officers_Lag UnempRate MedHHInc Poverty White Black i.Year i.PDID, robust
outreg2 using OLSTable.xls, addstat(Observations, e(N), R-squared, e(r2)) append

*OLS with controls and fe (VIOLENT)
reg ViolentCR Officers_Lag UnempRate MedHHInc Poverty White Black i.Year i.PDID, robust
outreg2 using OLSTable.xls, addstat(Observations, e(N), R-squared, e(r2)) append

*OLS with controls and fe (PROPERTY)
reg PropertyCR Officers_Lag UnempRate MedHHInc Poverty White Black i.Year i.PDID, robust
outreg2 using OLSTable.xls, addstat(Observations, e(N), R-squared, e(r2)) append

*/


/*CREATE MAIN DID RESULTS TABLE 
collapse (mean) OverallCrimeRate ViolentCR PropertyCR Treatment Post TreatPost UnempRate MedHHInc Poverty White Black, by(PDID Year) 

* DID no controls or fe
reg OverallCrimeRate Treatment Post TreatPost, robust 
outreg2 using DIDTable.xls, addstat(Observations, e(N), R-squared, e(r2)) replace 

*DID with fe 
reg OverallCrimeRate TreatPost i.Year i.PDID, robust 
outreg2 using DIDTable.xls, addstat(Observations, e(N), R-squared, e(r2)) append 

*DID with controls and fe 
reg OverallCrimeRate TreatPost UnempRate MedHHInc Poverty White Black i.Year i.PDID, robust 
outreg2 using DIDTable.xls, addstat(Observations, e(N), R-squared, e(r2)) append 

*DID with controls and fe (VIOLENT)
reg ViolentCR TreatPost UnempRate MedHHInc Poverty White Black i.Year i.PDID, robust 
outreg2 using DIDTable.xls, addstat(Observations, e(N), R-squared, e(r2)) append 

*DID with controls and fe (PROPERTY)
reg PropertyCR TreatPost UnempRate MedHHInc Poverty White Black i.Year i.PDID, robust 
outreg2 using DIDTable.xls, addstat(Observations, e(N), R-squared, e(r2)) append 


*/



/* CREATE OFFICERS DID RESULTS TABLE 
collapse (mean) Officers Treatment Post TreatPost UnempRate MedHHInc Poverty White Black, by(PDID Year) 

* DID no controls or fe
reg Officers Treatment Post TreatPost, robust 
outreg2 using OfficerTable.xls, addstat(Observations, e(N), R-squared, e(r2)) replace 

*DID with fe 
reg Officers TreatPost i.Year i.PDID, robust 
outreg2 using OfficerTable.xls, addstat(Observations, e(N), R-squared, e(r2)) append 

* DID with controls and fe 
reg Officers TreatPost UnempRate MedHHInc Poverty White Black i.Year i.PDID, robust 
outreg2 using OfficerTable.xls, addstat(Observations, e(N), R-squared, e(r2)) append 

*/


/* CREATE TWFE LAGGED TABLE 
bysort PoliceDept (Year): gen Officers_Lag = Officers[_n-1]
bysort PoliceDept (Year): gen Officers_Lag2 = Officers[_n-2]
bysort PoliceDept (Year): gen Officers_Lag3 = Officers[_n-3]

collapse (mean) OverallCrimeRate ViolentCR PropertyCR Officers Officers_Lag Officers_Lag2 Officers_Lag3 UnempRate MedHHInc Poverty White Black, by(PDID Year) 

*no lag
reg OverallCrimeRate Officers UnempRate MedHHInc Poverty White Black i.Year i.PDID, robust
outreg2 using TWFEPlaceboTable.xls, addstat(Observations, e(N), R-squared, e(r2)) replace

*1 year lag
reg OverallCrimeRate Officers_Lag UnempRate MedHHInc Poverty White Black i.Year i.PDID, robust
outreg2 using TWFEPlaceboTable.xls, addstat(Observations, e(N), R-squared, e(r2)) append

*2 year lag
reg OverallCrimeRate Officers_Lag2 UnempRate MedHHInc Poverty White Black i.Year i.PDID, robust
outreg2 using TWFEPlaceboTable.xls, addstat(Observations, e(N), R-squared, e(r2)) append

*3 year lag 
reg OverallCrimeRate Officers_Lag3 UnempRate MedHHInc Poverty White Black i.Year i.PDID, robust
outreg2 using TWFEPlaceboTable.xls, addstat(Observations, e(N), R-squared, e(r2)) append

*/




/*SYNTHETIC CONTROLS 

gen dummy = 0  
replace dummy = 1 if Year >= 2020 & Treatment == 1  

bysort PDID (Year): gen months_count = _N  
drop if months_count != 856

collapse (mean) OverallCrimeRate Officers, by(PDID Year)

tsset PDID Year

*Austin (2) 
synth_runner OverallCrimeRate Officers, trunit(2) trperiod(2020) gen_vars

effect_graphs ,trlinediff(-1) effect_gname(effectAus) tc_gname(Crime_Rate_Synth_Austin)

*Boston (4) 
synth_runner OverallCrimeRate Officers, trunit(4) trperiod(2020)

effect_graphs ,trlinediff(-1) effect_gname(effectBos) tc_gname(Crime_Rate_Synth_Boston)

/*Chicago (6) - No Police Data 
synth_runner OverallCrimeRate Officers, trunit(6) trperiod(2020)

effect_graphs ,trlinediff(-1) effect_gname(effect) tc_gname(Crime_Rate_Synth_Boston)
*/

*Denver (8)
synth_runner OverallCrimeRate Officers, trunit(8) trperiod(2020)

effect_graphs ,trlinediff(-1) effect_gname(effectDen) tc_gname(Crime_Rate_Synth_Denver)

/*Los Angeles (14) - No Police Data
synth_runner OverallCrimeRate Officers, trunit(14) trperiod(2020)

effect_graphs ,trlinediff(-1) effect_gname(effect) tc_gname(Crime_Rate_Synth_LosAngeles)
*/

*Louisville (15)
synth_runner OverallCrimeRate Officers, trunit(15) trperiod(2020)

effect_graphs ,trlinediff(-1) effect_gname(effectLou) tc_gname(Crime_Rate_Synth_Louisville)

*Memphis (16)
synth_runner OverallCrimeRate Officers, trunit(16) trperiod(2020)

effect_graphs ,trlinediff(-1) effect_gname(effectMem) tc_gname(Crime_Rate_Synth_Memphis)

*Milwaukee (17)
synth_runner OverallCrimeRate Officers, trunit(17) trperiod(2020)

effect_graphs ,trlinediff(-1) effect_gname(effectMil) tc_gname(Crime_Rate_Synth_Milwaukee)

*Minneapolis (18)
synth_runner OverallCrimeRate Officers, trunit(18) trperiod(2020)

effect_graphs ,trlinediff(-1) effect_gname(effectMin) tc_gname(Crime_Rate_Synth_Minneapolis)

*New York City (20)
synth_runner OverallCrimeRate Officers, trunit(20) trperiod(2020)

effect_graphs ,trlinediff(-1) effect_gname(effectNYC) tc_gname(Crime_Rate_Synth_NYC)

*Oklahoma City (21) 
synth_runner OverallCrimeRate Officers, trunit(21) trperiod(2020) 

effect_graphs ,trlinediff(-1) effect_gname(effectOKC) tc_gname(Crime_Rate_Synth_OklahomaCity)

*Portland (23)
synth_runner OverallCrimeRate Officers, trunit(23) trperiod(2020)

effect_graphs ,trlinediff(-1) effect_gname(effectPor) tc_gname(Crime_Rate_Synth_Portland)

*Seattle (26)
synth_runner OverallCrimeRate Officers, trunit(26) trperiod(2020)

effect_graphs ,trlinediff(-1) effect_gname(effectSea) tc_gname(Crime_Rate_Synth_Seattle)



/*








	
















