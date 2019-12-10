/******************************************************************************/
* Stats 506, Fall 2019														   ;
* Group Project - Group 3													   ;
*------------------------------------------------------------------------------;
* This script analyzes the question:										   ;
* 	"Do people diagnosed with diabetes consume less calories in US?"		   ;
* NHANES 2015-2016 data are used in this problem. 							   ;
* The script has following parts to complete the task:						   ;
* A. Merge source data														   ;
* 	 Merge information from:												   ;
*		Demographics - subject ID, age, gender								   ;
*		Dietary - subject ID, total calories (day 1), total calories (day 2)   ;
*		Examination - subject ID, BMI										   ;
*	    Questionnaire - subject ID, diabetes, pregnancy						   ;
*					  - vigorous/moderate/sedentary activity minutes		   ;
* B. Check missing patterns													   ;
*	 Check missing patterns of all variables								   ;
*	 Take a closer look at three physical activity variables				   ; 
* C. Handle top-coded age													   ;
*	 NHANES data top-coded age at 80 and above. 							   ;
*	 Restrict it to 12-79 years old.							  			   ;
* D. Transformation of response variable									   ;
*	 Examine the normality of response variable								   ;
*	 Determine whether a transformation is needed							   ;
* E. Initial model to examine collinearity - use Day 1 only					   ;
*	 Use day 1 data only to fit a linear regressio model					   ;
*	 Determine if multicollinearity issue exists							   ;
*	 If yes, handle if appropriately										   ;
* F. Linear mixed model to account for both day 1 and day 2					   ;
*	 Fit a linear mixed model to include both days data						   ;
*	 Include a random intercept for each subject							   ;
*	 Also, obtain marginal effects for diabetes and gender (male)			   ;
*------------------------------------------------------------------------------;
* Author: Jie Cao (caojie@umich.edu)										   ;
* Last updated on: Dec 10, 2019												   ;
/******************************************************************************/


* 80: -------------------------------------------------------------------------;


/* Data directory ----------------------------------------------------------- */
* List of XPT data downloaded from 2015 - 2016 NHANES;
libname DEMO xport "M:\506\data\XPT\DEMO_I.XPT"; 
libname DIQ xport "M:\506\data\XPT\DIQ_I.XPT";
libname PAQ xport "M:\506\data\XPT\PAQ_I.XPT";
libname DR1 xport "M:\506\data\XPT\DR1TOT_I.XPT";
libname DR2 xport "M:\506\data\XPT\DR2TOT_I.XPT";
libname BMX xport "M:\506\data\XPT\BMX_I.XPT";

* Directory to save datasets extracted from XPT files; 
libname NH "M:\506\data\SAS"; 


/* Extract XPT files and save as SAS datasets ------------------------------- */
proc copy in = DEMO out = NH;
run;
proc copy in = DIQ out = NH;
run;
proc copy in = PAQ out = NH;
run;
proc copy in = DR1 out = NH;
run;
proc copy in = DR2 out = NH;
run;
proc copy in = BMX out = NH;
run;


/* Formats ------------------------------------------------------------------- */
proc format;
	/* A format to flag numeric varibles with missing status */
	value missfmt 
		. = "Missing" 
		other = "Non-missing";
	/* Gender format */
	value male
		0 = "Female"
		1 = "Male";
run;


/* Prepare working data ------------------------------------------------------ */

***************************;
* A. Merge source data     ;
****************************

* Dietary day 1 interview plus needed variables;
proc sql;
	create table dr1 as
	select dm.SEQN as subject,
		   1 as day,   
			(case 
			 /* DIQ010 = 2: doctor confirmed no diabetes */ 
			 when dm.DIQ010 = 2 then 0 
			 /* DIQ010 = 1 or 3: doctor confirmed diabetes (1) or borderline (3) */
			 else 1
			 end) as diabetes, 
		   demo.RIDAGEYR as ageyr , 
			(case
			 when demo.RIAGENDR = 1 then 1 
			 when demo.RIAGENDR = 2 then 0 
			 else .
			 end) as male format male., 
		   bm.BMXBMI as bmi, 
		   pa.PAD615 as vigorous_min, 
		   pa.PAD630 as moderate_min, 
		   pa.PAD680 as sedentary_min, 
		   dr1.DR1TKCAL as tot_cal
		    
	from NH.Diq_i dm 
	left join NH.Demo_i demo on dm.SEQN = demo.SEQN
	left join NH.Bmx_i bm on dm.SEQN = bm.SEQN
	left join NH.Paq_i pa on dm.SEQN = pa.SEQN
	left join NH.Dr1tot_i dr1 on dm.SEQN = dr1.SEQN
	
	/* Include subjects with known answers to diabete diagnosis &
	   exclude participants confirmed with pregnancy */
	where dm.DIQ010 in (1, 2, 3) and demo.RIDEXPRG NE 1;
quit;

* Dietary day 2 interview plus needed variables; 
proc sql;
	create table dr2 as
	select dm.SEQN as subject,
		   2 as day,   
			(case 
			 /* DIQ010 = 2: doctor confirmed no diabetes */ 
			 when dm.DIQ010 = 2 then 0 
			 /* DIQ010 = 1 or 3: doctor confirmed diabetes (1) or borderline (3) */
			 else 1
			 end) as diabetes, 
		   demo.RIDAGEYR as ageyr,  
			(case
			 when demo.RIAGENDR = 1 then 1 
			 when demo.RIAGENDR = 2 then 0 
			 else .
			 end) as male format male.,  
		   bm.BMXBMI as bmi, 
		   pa.PAD615 as vigorous_min, 
		   pa.PAD630 as moderate_min, 
		   pa.PAD680 as sedentary_min, 
		   dr2.DR2TKCAL as tot_cal
		    
	from NH.Diq_i dm 
	left join NH.Demo_i demo on dm.SEQN = demo.SEQN
	left join NH.Bmx_i bm on dm.SEQN = bm.SEQN
	left join NH.Paq_i pa on dm.SEQN = pa.SEQN
	left join NH.Dr2tot_i dr2 on dm.SEQN = dr2.SEQN

	/* Include subjects with known answers to diabete diagnosis &
	   exclude participants confirmed with pregnancy */
	where dm.DIQ010 in (1, 2, 3) and demo.RIDEXPRG NE 1;
quit;

* Combine two days' data; 
proc sql;
	create table dm_cal as
	select * 
	from dr1 
	outer union corr
	select * 
	from dr2
	order by subject, day;
quit;


**********************************************;
* B. Check missing patterns 				  ;
**********************************************;

* Add variables to count number of missing; 
data check;
	set dm_cal;
	/* Number of missing among three physical activity minutes 
	   for each participant */
	mins_miss = cmiss(of vigorous_min--sedentary_min);
	/* Number of missing among all (numeric) variables we may 
	   potentially use for each participant */
	nmiss = cmiss(of diabetes--tot_cal);
run;
* Tabulate number of missing;
proc sort data = check;
	by day;
run;
proc freq data = check;
	tables mins_miss nmiss;
	by day;
run;
*** 1064 (11.2%) have complete three physical activity minutes data, both day 1 and day 2; 
*** 979 (10.3%) have complete all numeric data for day 1;
*** 801 (8.4%) have complete all numeric data for day 2;  

* Check missing patterns for numeric variables we are interested in;
proc freq data = check;
	format diabetes--tot_cal missfmt.; 
	tables diabetes--tot_cal / missing missprint nocum;
	by day;
run;
*** No missing in diabetes (by nature of merging process), age, gender; 
*** BMI: 818 (8.6%) missing in both day 1 and day 2;  
*** Vigorous_min: 8156 (85.8%) missing in both day 1 and day 2;  
*** Moderate_min: 6942 (73.1%) missing in both day 1 and day 2;
*** Sedentary_min: 2624 (27.6%) missing in both day 1 and day 2; 
*** tot_cal: 1452 (15.3%) missing in day 1, 2862 (30.1%) in day 2;  

*--------------------------------------------------------------------------------;
* According to missing patterns we observed above, we decide not to use 	     ;
* vigorous activity minutes and moderate activity minutes due to large amount of ; 
* missing.																		 ;																		   
*--------------------------------------------------------------------------------;


********************************;
* C. Handle top-coded age	    ;
********************************;
/* NHANES top-coded age variable at 80 years, therefore, we consider restrict participant age range */ 
data dm_cal;
	set dm_cal;
	/* Restrict to age 12-79 */
	where 12 <= ageyr < 80;
run;


*******************************************
* D. Transformation of response variable  ;
******************************************;
/* Examine the distribution of response variable */
proc univariate data = dm_cal;
	var tot_cal;
	histogram tot_cal / normal;
	class day;
run;
* Approximatley normal, no transformation needed;



/* Modeling ----------------------------------------------------------------- */

************************************************************;
* E. Initial model to examine collinearity - use Day 1 only ;
************************************************************;
data dm_cal_final dr1_final dr2_final;
	set dm_cal(drop = vigorous_min moderate_min);
	/* Remove observations with missing in any of the variables*/
	if cmiss(of _all_) then delete;
	
	/* Output two day's, day 1 only and day 2 only data */
	output dm_cal_final;
	if day = 1 then output dr1_final;
	if day = 2 then output dr2_final;
run;

/* Examine the correlation matrix */
proc corr data = dr1_final;
	var diabetes ageyr male bmi sedentary_min;
run;
/* Multicollinearity Investigation of VIF */
proc reg data = dr1_final;
	model tot_cal = diabetes ageyr male bmi sedentary_min / vif tol collin; 
run; 


************************************************************;
* F. Linear mixed model to account for both day 1 and day 2 ;
************************************************************;
proc mixed data = dm_cal_final;
	class diabetes male;
	model tot_cal = diabetes ageyr male bmi sedentary_min / solution;
	random intercept / subject = subject;
	lsmeans diabetes male / at means;
run;


* 80: -------------------------------------------------------------------------;
