--Identifying the population of interest
	--patient has two or more encounter diagnoses of type 2 diabetes at least 30 days apart
	--Age 18+
	--Research consented
	--encounters between 1/1/2016 and 1/1/2024
	--no excluding diagnoses

/*
Descriptions of tables used in this script:
LHS_DIAGNOSIS_DIM - A dimension table of diagnosis records and their corresponding ICD-10 codes. One row per diagnosis record and ICD-10 code (dx_id, code).
LHS_DIAGNOSIS_EVENT_FACT - A fact table of all assigned patient diagnoses. One row per assigned diagnosis (dx_id, pat_id, start_date).
LHS_PATIENT - A table of patient demographics. One row per patient (pat_id).
LHS_MDM_REGISTRY - A table for deduplicating patient records. This only exists because our datamart combines records from two different Epic instances. One row per patient per Epic instance. (pat_id, source_system)
LHS_RESEARCH_CONSENT - A table indicating whether patients have opted in or out of research. One row per patient (pat_id).
LHS_PATIENT_ADDRESS - A table of patient addresses over time. One row per patient per address with start and end dates (pat_id, start_datae).
LHS_HTWTBMI_PAT_ENC - A table of the ending height, weight, and bmi for each encounter. One row per encounter (pat_enc_csn_id).
LHS_ENCOUNTER - A table of patient encounters that involve patient interaction with providers, either face-to-face or virtual (pat_enc_csn_id).
LHS_SOCIAL - A table of social determinants of health over time. One row per encounter (pat_enc_csn_id).
LHS_LABS_PROCESSED - A table of processed lab results in which lab components representing the same general test are grouped together, any necessary unit conversions are made and result values are converted to numeric format. One row per lab result (order_proc_id, component_id).
LHS_ORDER_MED - A table of all ordered medications. One row per medication order (order_id).
LHS_RXNORM_LOOKUP - A lookup/crosswalk table that links rxnorm ingredients to medication records. One row per rxnorm ingredient per medication record (medication_id, rxnorm_code).
LHS_MEDICATIONS - A dimension table of medication records. One row per medication record (medication_id).
*/
----------------------------------------------------------

--This query identifies all the diagnosis records of interest. These will be used to join to patient diagnoses.
select source_system, dx_id, case when CODE in ('E11' , 'e11.9', 'e08.10','e11.01', 'e11.10','e11.65', 'e13.65', 'e08.65') then 'diabetes'
when code like 'm05.%' then 'rheumatologic_disease'
when code in ( 'I10', 'I15' ) then 'hypertension'
when code like 'K70.%' or code like 'K71.%' or code like 'K72.%' or code like 'K73.%' or code like 'K74.%' 
	or code like 'K75.%' or code like 'K76.%' or code like 'K77.%' then 'liver_disease'
when code like 'I25.%' or code like 'I50.%' then 'cardiac_disease'
when code in ('N17.9', 'N17.8', 'N17.0','N17.1', 'N17.2')  then 'aki'
when code in ('Q61.2', 'N04', 'N05.9') then 'nondiabetic_kidney_disease'
when code in ('E11.319', 'E11.40', 'I73.9', 'I67.9') then 'diabetes_complications'
when code like 'n19.%' or code like 'N18.3%' or code like 'N18.4%' or code like 'N18.5%' or code in ('Z99.2', 'Z49.01', 'Z49.02','e11.21', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E08.21', 'E13.21', 'r80.9', 'N18.6') then 'diabetic_nephropathy' end as dx_type
into #dbdx --drop table #dbdx
from LHS_DIAGNOSIS_DIM
where CODE in ('E11' , 'e11.9', 'e08.10','e11.01', 'e11.10','e11.65', 'e13.65', 'e08.65') or code like 'm05.%'
or code like 'K70.%' or code like 'K71.%' or code like 'K72.%' or code like 'K73.%' or code like 'K74.%'
or code like 'K75.%' or code like 'K76.%' or code like 'K77.%' 
or code like 'I25.%' or code like 'I50.%'
or code like 'n19.%' or code like 'N18.3%' or code like 'N18.4%' or code like 'N18.5%'
or code in ('N17.9', 'N17.8', 'N18.6', 'Z99.2', 'Z49.01', 'Z49.02')
or code in ('Q61.2', 'N04', 'N05.9')
or code in ('E11.319', 'E11.40', 'I73.9', 'I67.9')
or code in ('e11.21', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E08.21', 'E13.21', 'r80.9')
or code in ( 'I10', 'I15' )
;
--Table of all the patient diabetes diagnoses. Will be used to identify the base patient population.
select distinct p.mdm_link_id, a.start_date
into #all_db_dx --drop table #all_db_dx
from LHS_DIAGNOSIS_EVENT_FACT a
inner join #dbdx b on a.DX_ID = b.DX_ID and a.source_system = b.SOURCE_SYSTEM
--The below table is used to attach a unique patient identifier (mdm_link_id). Because we have merged data from two different Epic instances with patient overlap,
--the normal pat_id is not sufficient. Other systems without this issue can likely ignore this table and use a different unique patient ID, here and in the queries below.
inner join LHS_MDM_REGISTRY p on a.PAT_ID = p.pat_id and a.source_system = p.SOURCE_SYSTEM
where (a.type in ('Encounter diagnosis', 'Problem List') or (a.type = 'Billing Diagnosis' and a.isprimary is not null)) --clinical and billing diagnoses only
and b.dx_type = 'diabetes' and a.start_date < '1/1/2025'
;

--Table of all the patient exclusion diagnoses (nondiabetic kidney disease)
select p.mdm_link_id, min(a.start_date) as start_date
into #all_exclusion_dx --drop table #all_exclusion_dx
from LHS_DIAGNOSIS_EVENT_FACT a
inner join #dbdx b on a.DX_ID = b.DX_ID and a.source_system = b.SOURCE_SYSTEM
inner join LHS_MDM_REGISTRY p on a.PAT_ID = p.pat_id and a.source_system = p.SOURCE_SYSTEM
where (a.type in ('Encounter diagnosis', 'Problem List') or (a.type = 'Billing Diagnosis' and a.isprimary is not null))
and b.dx_type in ('nondiabetic_kidney_disease')
and a.start_date < '1/1/2025'
group by p.mdm_link_id
;
--Main patients table that brings in demographic info and performs relevant exclusions.
select a.mdm_link_id, a.earliest_diabetes_dx_date, pat.dob, pat.death_date, pat.ethnic_group, pat.patient_race_1, pat.language, pat.legal_sex, excl_dx.start_date as earliest_exclusion_dx_date
into #patients --drop table #patients
from 
--This subquery identifies patients with two or more diabetes diagnoses at least 30 days apart.
(select a1.mdm_link_id, min(a1.start_date) as earliest_diabetes_dx_date from #all_db_dx a1 
	inner join #all_db_dx b1 on a1.MDM_LINK_ID = b1.MDM_LINK_ID and DATEDIFF(day, a1.start_date, b1.start_date) > 30 
	group by a1.mdm_link_id) a
--Subquery to identify most recent demographic info for patients. Likely can be a direct table join instead of a subquery in most systems.
inner join (select mdm.mdm_link_id, a1.LEGAL_SEX, a1.dob, a1.DEATH_DATE, a1.PATIENT_RACE_1, a1.ETHNIC_GROUP, a1.LANGUAGE, ROW_NUMBER() over (partition by a1.mdm_link_id order by a1.source_system asc) rn 
	from LHS_PATIENT a1 inner join LHS_MDM_REGISTRY mdm on a1.PAT_ID = mdm.pat_id and a1.source_system = mdm.SOURCE_SYSTEM) pat on a.MDM_LINK_ID = pat.MDM_LINK_ID and pat.rn = 1
inner join LHS_RESEARCH_CONSENT rc on a.MDM_LINK_ID = rc.MDM_LINK_ID
left join #all_exclusion_dx excl_dx on a.MDM_LINK_ID = excl_dx.mdm_link_id 
where datediff(day, pat.dob, a.earliest_diabetes_dx_date)/365.25 >= 18 --patient is 18+ when diagnosed with diabetes
and (excl_dx.start_date is null or (excl_dx.start_date > a.earliest_diabetes_dx_date and excl_dx.start_date > '1/1/2016')) --patient does not have excluding diagnoses prior to study
--Outcome subquery for patients with two or more diabetic nephropathy diagnoses at least 30 days apart.
and rc.RESEARCH_OPT_OUT_STATUS = 'IN' --patient is research consented
;
--Table of all relevant comorbidity diagnoses for the eligible patient set.
select distinct p.mdm_link_id, b.dx_type, a.start_date
into #all_other_dx --drop table #all_other_dx
from LHS_DIAGNOSIS_EVENT_FACT a
inner join #dbdx b on a.DX_ID = b.DX_ID and a.source_system = b.SOURCE_SYSTEM
inner join LHS_MDM_REGISTRY p on a.PAT_ID = p.pat_id and a.source_system = p.SOURCE_SYSTEM
inner join #patients pat on p.MDM_LINK_ID = pat.MDM_LINK_ID
where (a.type in ('Encounter diagnosis', 'Problem List') or (a.type = 'Billing Diagnosis' and a.isprimary is not null))
and b.dx_type in ('rheumatologic_disease','liver_disease','cardiac_disease','diabetes_complications', 'hypertension', 'aki') and a.start_date < '1/1/2025'
;
--For each comorbidity category except aki, the earliest diagnosis date for patients with at least 2 diagnosis 30 days or more apart.
select a.mdm_link_id, a.dx_type, min(a.start_date) as earliest_dx_date
into #comorbid_dx
from #all_other_dx a
inner join #all_other_dx b on a.MDM_LINK_ID = b.MDM_LINK_ID and a.dx_type = b.dx_type and DATEDIFF(day, a.start_date, b.start_date) > 30 
where a.dx_type != 'aki'
group by a.MDM_LINK_ID, a.dx_type
;

--A set of encounters during the study period for eligible patients. Temporal data such as BMI, insurance, address is included. Also to be used for censoring.
select a.mdm_link_id, b.source_system + cast(b.PAT_ENC_CSN_ID as varchar) as encounter_id --unique encounter_id (source_system is needed only because we have multiple Epic instances)
, b.effective_date_dttm --The encounter date
, b.financial_class --Basic insurance info
, addr.zip
, coalesce(bmi.BMI, round(((bmi.weight/16.00)/(square(try_cast(bmi.height as numeric))))*703.00,2)   ) bmi --if unavailable, calculated based on height (inches) and weight (oz)
, case when b.PAT_CLASS in ('Inpatient', 'Emergency', 'Observation') then b.PAT_CLASS else 'Outpatient' end as encounter_type
into #encounters --drop table #encounters
from #patients a
inner join LHS_MDM_REGISTRY mdm on a.MDM_LINK_ID = mdm.MDM_LINK_ID
inner join LHS_ENCOUNTER b on mdm.PAT_ID = b.pat_id and mdm.SOURCE_SYSTEM = b.SOURCE_SYSTEM
left join LHS_PATIENT_ADDRESS addr on b.pat_id = addr.pat_id and b.SOURCE_SYSTEM = addr.SOURCE_SYSTEM and b.ENCOUNTER_START between addr.address_start_date and coalesce(addr.address_end_date , '1/1/2099')
left join LHS_HTWTBMI_PAT_ENC bmi on b.PAT_ENC_CSN_ID = bmi.PAT_ENC_CSN_ID and b.SOURCE_SYSTEM = bmi.SOURCE_SYSTEM
where b.EFFECTIVE_DATE_DTTM >= '1/1/2015' and b.EFFECTIVE_DATE_DTTM < '1/1/2025'
;
--Tobacco use is not always entered for every encounter, so this query finds the most recent data for the patient within the past year prior to the encounter date.
select z.mdm_link_id, z.encounter_id, z.smoking_tob_use
into #social
from (
select a.MDM_LINK_ID, a.encounter_id, soc.smoking_tob_use, ROW_NUMBER() over (partition by a.mdm_link_id, a.encounter_id order by soc.contact_date desc) rn
from #encounters a
inner join LHS_MDM_REGISTRY mdm on a.MDM_LINK_ID = mdm.MDM_LINK_ID
inner join LHS_SOCIAL soc on mdm.PAT_ID = soc.pat_id and mdm.SOURCE_SYSTEM = soc.source_system and soc.contact_date between DATEADD(year,-1,a.EFFECTIVE_DATE_DTTM) and a.EFFECTIVE_DATE_DTTM
) z
where z.rn = 1
;
--The number of aki dx that are 60 or more days apart. 
select b.mdm_link_id, b.start_date, ROW_NUMBER() over (partition by b.mdm_link_id order by b.start_date) rn
into #aki_dx
from (select *, lag(a.start_date) over (partition by mdm_link_id order by a.start_date) as prev_aki_date
	from #all_other_dx a
	where a.dx_type = 'aki') b
where DATEDIFF(day, coalesce(b.prev_aki_date, '1/1/1901'), b.start_date) >= 60
;
--Patient labs
select a.mdm_link_id, cast(a.result_time as date) as result_time, a.grouped_lab_name, a.component_result_numeric_conversion as result
into #labs --drop table #labs
from LHS_LABS_PROCESSED a
inner join #patients p on a.MDM_LINK_ID = p.MDM_LINK_ID
where a.grouped_lab_name in ('LAB_HBA1C','LAB_GFR', 'LAB_CYSTATIN C', 'LAB_CREATININE') and a.component_result_numeric_conversion
 is not null

; 

--Table of all the patient diabetic nephropathy diagnoses. 
select distinct p.mdm_link_id, a.start_date
into #all_nephropathy_dx --drop table #all_nephropathy_dx
from LHS_DIAGNOSIS_EVENT_FACT a
inner join #dbdx b on a.DX_ID = b.DX_ID and a.source_system = b.SOURCE_SYSTEM
inner join LHS_MDM_REGISTRY p on a.PAT_ID = p.pat_id and a.source_system = p.SOURCE_SYSTEM
where (a.type in ('Encounter diagnosis', 'Problem List') or (a.type = 'Billing Diagnosis' and a.isprimary is not null))
and b.dx_type = 'diabetic_nephropathy' and a.start_date < '1/1/2025'
;

--Determination of nephropathy using diagnoses and labs.
--This is our outcome, and it will also be used to exclude patients who had diabetic nephropathy 
--prior to the study period.


select z.mdm_link_id, min(z.earliest_nephropathy_time) earliest_nephropathy_time
into #nephropathy_outcome --drop table #nephropathy_outcome
from (select a.MDM_LINK_ID, min(a.result_time) as earliest_nephropathy_time
	from #labs a
	inner join #labs b on a.MDM_LINK_ID = b.MDM_LINK_ID and a.grouped_lab_name = b.grouped_lab_name and b.RESULT_TIME > DATEADD(day, 30,a.result_time)
		and b.result > 1.4
	where a.grouped_lab_name = 'LAB_CREATININE' and a.result > 1.4 and b.result > 1.4
	group by a.MDM_LINK_ID
	union
	select a.MDM_LINK_ID, min(a.result_time) as earliest_nephropathy_time
	from #labs a
	inner join #labs b on a.MDM_LINK_ID = b.MDM_LINK_ID and a.grouped_lab_name = b.grouped_lab_name and b.RESULT_TIME > DATEADD(day, 30,a.result_time)
	where a.grouped_lab_name = 'LAB_Cystatin C' and a.result > 1.2 and b.result > 1.2
	group by a.MDM_LINK_ID
	union
	select a.MDM_LINK_ID, min(a.result_time) as earliest_nephropathy_time
	from #labs a
	inner join #labs b on a.MDM_LINK_ID = b.MDM_LINK_ID and a.grouped_lab_name = b.grouped_lab_name and b.RESULT_TIME > DATEADD(day, 30,a.result_time)
	where a.grouped_lab_name = 'LAB_GFR' and a.result < 60 and b.result < 60
	group by a.MDM_LINK_ID
	union
	select a1.mdm_link_id, min(a1.start_date) as earliest_nephropathy_time
	from #all_nephropathy_dx a1 inner join #all_nephropathy_dx b1 on a1.MDM_LINK_ID = b1.MDM_LINK_ID and DATEDIFF(day, a1.start_date, b1.start_date) > 30 
	group by a1.MDM_LINK_ID
) z
group by z.MDM_LINK_ID

;
--Medication orders for meds to preserve kidney function
select distinct mdm.mdm_link_id, a.med_start_date, a.end_date
, case when b.RXNORM_CODE in (1091643, 18867, 1998, 214354, 29046, 30131, 321064, 325646, 35208, 35296, 3827, 3829, 38454, 50166, 52175, 54552, 69749, 73494, 83515, 83818)	then 'RAAS'
when b.RXNORM_CODE in (1545653, 1373458, 1488564, 1488564, 1545653, 1545653, 1373458, 1373458, 1373458, 1545653, 1992672, 1992672, 1545653, 1992672, 1488564, 1545653, 1992672, 1488564, 1373458, 1545653, 1545653, 1488564, 1373458, 1373458, 1545653, 1488564, 1545653, 1488564, 1373458, 1545653, 1373458, 1488564, 1373458, 1992672, 1545653, 1992672, 2627044) then 'SGLT2_inhibitor'
when b.RXNORM_CODE in (475968, 1991302, 60548, 1551291, 1991302, 1991302, 1534763, 60548, 60548, 1991302, 1534763, 475968, 1551291, 1551291, 1991302, 475968, 1440051, 1440051, 475968, 1991302, 1551291, 475968, 60548, 1551291, 1440051, 60548, 475968, 1534763, 60548, 1991302, 1991302) then 'GLP_1_RA'
when b.RXNORM_CODE in (2562811, 298869, 9997) then 'MRA' end as medication_type
into #all_db_meds --drop table #all_db_meds
from LHS_ORDER_MED a --medication orders
inner join LHS_RXNORM_LOOKUP b on a.source_system = b.SOURCE_SYSTEM and a.MEDICATION_ID = b.MEDICATION_ID --rxnorm codes for medication records
inner join LHS_MEDICATIONS med on a.source_system = med.SOURCE_SYSTEM and a.MEDICATION_ID = med.MEDICATION_ID --medication info
inner join LHS_MDM_REGISTRY mdm on a.PAT_ID = mdm.pat_id and a.SOURCE_SYSTEM = mdm.SOURCE_SYSTEM
inner join #patients p on mdm.MDM_LINK_ID = p.MDM_LINK_ID
where b.RXNORM_CODE in 
(1091643, 18867, 1998, 214354, 29046, 30131, 321064, 325646, 35208, 35296, 3827, 3829, 38454, 50166, 52175, 54552, 69749, 73494, 83515, 83818
,1545653, 1373458, 1488564, 1488564, 1545653, 1545653, 1373458, 1373458, 1373458, 1545653, 1992672, 1992672, 1545653, 1992672, 1488564, 1545653, 1992672, 1488564, 1373458, 1545653, 1545653, 1488564, 1373458, 1373458, 1545653, 1488564, 1545653, 1488564, 1373458, 1545653, 1373458, 1488564, 1373458, 1992672, 1545653, 1992672, 2627044
,475968, 1991302, 60548, 1551291, 1991302, 1991302, 1534763, 60548, 60548, 1991302, 1534763, 475968, 1551291, 1551291, 1991302, 475968, 1440051, 1440051, 475968, 1991302, 1551291, 475968, 60548, 1551291, 1440051, 60548, 475968, 1534763, 60548, 1991302, 1991302
,2562811, 298869, 9997)
and case when b.RXNORM_CODE = 9997 and med.ROUTE = 'topical' then 1 else 0 end != 1 --removes topical spironolactone
and a.ORDER_STATUS in ('Sent', 'Suspend')
and a.ORDERING_MODE_C = 1
and a.order_class in ('Normal','Fax','Local Print','E-Prescribe','Print','InstyMeds')
;

select a.*, b.earliest_nephropathy_time
into #patients_final
from #patients a
left join #nephropathy_outcome b on a.MDM_LINK_ID = b.MDM_LINK_ID
where (b.earliest_nephropathy_time is null or (a.earliest_diabetes_dx_date < b.earliest_nephropathy_time and b.earliest_nephropathy_time > '1/1/2016')) --Patient does not have a diabetic nephropathy diagnoses before study period
;

--export each of these queries
select *
from #patients_final
;
select a.*, b.smoking_tob_use, c.number_of_aki
from #encounters a
inner join #patients_final p on a.MDM_LINK_ID = p.MDM_LINK_ID
left join #social b on a.encounter_id = b.encounter_id
left join (select enc.encounter_id, max(aki.rn) as number_of_aki
	from #encounters enc
		inner join #aki_dx aki on enc.MDM_LINK_ID = aki.MDM_LINK_ID and enc.EFFECTIVE_DATE_DTTM>= aki.start_date
		group by enc.encounter_id) c on a.encounter_id = c.encounter_id

;
select a.*
from #all_db_meds a
inner join #patients_final p on a.MDM_LINK_ID = p.MDM_LINK_ID
;
select a.*
from #comorbid_dx a
inner join #patients_final p on a.MDM_LINK_ID = p.MDM_LINK_ID
;
select a.*
from #labs a
inner join #patients_final p on a.MDM_LINK_ID = p.MDM_LINK_ID
