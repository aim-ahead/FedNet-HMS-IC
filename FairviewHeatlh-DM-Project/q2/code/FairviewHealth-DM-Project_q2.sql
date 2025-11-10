-- Drop existing tables
if OBJECT_ID(N'AAFN_DiagnosisSummary', N'U') is not null drop table AAFN_DiagnosisSummary;
if OBJECT_ID(N'AAFN_MedicationSummary', N'U') is not null drop table AAFN_MedicationSummary;
if OBJECT_ID(N'AAFN_LabSummary', N'U') is not null drop table AAFN_LabSummary;
if OBJECT_ID(N'AAFN_LabValueSummary', N'U') is not null drop table AAFN_LabValueSummary;


-- Create new tables to save results

create table AAFN_DiagnosisSummary (
	ICD10Code varchar(50) not null,
	FirstDate date,
	LastDate date,
	NumberOfFacts int,
	NumberOfPatients int,
	NumberOfPatientsIn2025 int,
	PatientsWithTwoPlusDiagDates int,
	primary key (ICD10Code)
);

create table AAFN_MedicationSummary (
	RxNormCode varchar(50) not null,
	FirstDate date,
	LastDate date,
	NumberOfFacts int,
	NumberOfPatients int,
	NumberOfPatientsIn2025 int,
	primary key (RxNormCode)
);

create table AAFN_LabSummary (
	LoincCode varchar(50) not null,
	FirstDate date,
	LastDate date,
	NumberOfFacts int,
	NumberOfPatients int,
	NumberOfPatientsIn2025 int,
	primary key (LoincCode)
);

create table AAFN_LabValueSummary (
	LoincCode varchar(50) not null,
	LabUnits varchar(50) not null,
	FirstDate date,
	LastDate date,
	NumberOfNumericResults int,
	MinValue numeric(18,5),
	MaxValue numeric(18,5),
	MeanValue numeric(18,5),
	StDevValue numeric(18,5)
	primary key (LoincCode, LabUnits)
);


-- Generate diagnosis summary
;with Diagnosis as (
	-- Point to your database table containing ICD-10 diagnosis codes
	-- Include all diagnoses: encounter, billing, problem list, etc.
	-- Replace dates earlier than Jan 1, 1950, with null
	select patient_num as PatientNum, 
		concept_cd as ICD10Code, 
		(case when start_date<cast('1950-01-01' as date) then null else start_date end) as StartDate
	from observation_fact
	where concept_cd like 'ICD10CM:%'
), PatientDiagnosis as (
	-- Get patient-diagnosis pairs
	select PatientNum, 
		ICD10Code,
		cast(min(StartDate) as date) FirstDate,
		cast(max(StartDate) as date) LastDate,
		count(distinct cast(StartDate as date)) NumberOfFacts,
		max(case when datepart(yy,StartDate)=2025 then 1 else 0 end) HasDateIn2025
	from Diagnosis
	group by ICD10Code, PatientNum
)
insert into AAFN_DiagnosisSummary(ICD10Code, FirstDate, LastDate, NumberOfFacts, NumberOfPatients, NumberOfPatientsIn2025, PatientsWithTwoPlusDiagDates)
	-- Calculate counts for each diagnosis code; mask codes with fewer than 10 patients
	select ICD10Code,
		min(FirstDate) FirstDate,
		max(LastDate) LastDate,
		sum(NumberOfFacts) NumberOfFacts,
		count(*) NumberOfPatients,
		(case when sum(HasDateIn2025)>=10 then sum(HasDateIn2025) else -1 end) NumberOfPatientsIn2025,
		(case when sum(case when NumberOfFacts>=2 then 1 else 0 end)>=10
				then sum(case when NumberOfFacts>=2 then 1 else 0 end)
				else -1 end) PatientsWithTwoPlusDiagDates
	from PatientDiagnosis
	group by ICD10Code
	having count(*)>=10;


-- Generate medication summary
;with Medication as (
	-- Point to your database table containing medications mapped to RxNorm codes
	-- Include all medications: ordered, dispensed, discharge, etc.
	-- Replace dates earlier than Jan 1, 1950, with null
	select patient_num as PatientNum, 
		concept_cd as RxNormCode,
		(case when start_date<cast('1950-01-01' as date) then null else start_date end) as StartDate
	from observation_fact
	where concept_cd like 'RxNorm:%'
), PatientMedication as (
	-- Get patient-medication pairs
	select PatientNum, 
		RxNormCode, 
		cast(min(StartDate) as date) FirstDate,
		cast(max(StartDate) as date) LastDate,
		count(*) NumberOfFacts,
		max(case when datepart(yy,StartDate)=2025 then 1 else 0 end) HasDateIn2025
	from Medication
	group by RxNormCode, PatientNum
)
insert into AAFN_MedicationSummary(RxNormCode, FirstDate, LastDate, NumberOfFacts, NumberOfPatients, NumberOfPatientsIn2025)
	-- Calculate counts for each medication code; mask codes with fewer than 10 patients
	select RxNormCode,
		min(FirstDate) FirstDate,
		max(LastDate) LastDate,
		sum(NumberOfFacts) NumberOfFacts,
		count(*) NumberOfPatients,
		(case when sum(HasDateIn2025)>=10 then sum(HasDateIn2025) else -1 end) NumberOfPatientsIn2025
	from PatientMedication
	group by RxNormCode
	having count(*)>=10;


-- Generate lab summary
;with Lab as (
	-- Point to your database table containing laboratory test results mapped to loinc codes
	-- Replace dates earlier than Jan 1, 1950, with null
	select patient_num as PatientNum, 
		concept_cd as LoincCode,
		(case when start_date<cast('1950-01-01' as date) then null else start_date end) as StartDate
	from observation_fact
	where concept_cd like 'LOINC:%'
), PatientLab as (
	-- Get patient-lab pairs
	select PatientNum, 
		LoincCode,
		cast(min(StartDate) as date) FirstDate,
		cast(max(StartDate) as date) LastDate,
		count(*) NumberOfFacts,
		max(case when datepart(yy,StartDate)=2025 then 1 else 0 end) HasDateIn2025
	from Lab
	group by LoincCode, PatientNum
)
insert into AAFN_LabSummary(LoincCode, FirstDate, LastDate, NumberOfFacts, NumberOfPatients, NumberOfPatientsIn2025)
	-- Calculate counts for each lab code; mask codes with fewer than 10 patients
	select LoincCode,
		min(FirstDate) FirstDate,
		max(LastDate) LastDate,
		sum(NumberOfFacts) NumberOfFacts,
		count(*) NumberOfPatients,
		(case when sum(HasDateIn2025)>=10 then sum(HasDateIn2025) else -1 end) NumberOfPatientsIn2025
	from PatientLab
	group by LoincCode
	having count(*)>=10;


-- Generate lab value summary
;with LabValue as (
	-- Point to your database table containing laboratory test results mapped to loinc codes
	-- Replace dates earlier than Jan 1, 1950, with null
	-- Replace "nval_num" with the column name containing numeric lab results
	select concept_cd as LoincCode,
		isnull(units_cd,'@') as LabUnits,
		(case when start_date<cast('1950-01-01' as date) then null else start_date end) as StartDate,
		cast(nval_num as numeric(18,5)) as ResultValue
	from observation_fact
	where concept_cd like 'LOINC:%'
		and isnumeric(nval_num)=1
)
insert into AAFN_LabValueSummary(LoincCode, LabUnits, FirstDate, LastDate, NumberOfNumericResults, MinValue, MaxValue, MeanValue, StDevValue)
	-- Calculate summary statistics on units and values for each lab code; mask code-unit pairs with fewer than 10 patients
	select LoincCode,
		LabUnits,
		min(StartDate) FirstDate,
		max(StartDate) LastDate,
		count(*) NumberOfNumericResults,
		min(ResultValue) MinValue,
		max(ResultValue) MaxValue,
		avg(ResultValue) MeanValue,
		stdev(ResultValue) StDevValue
	from LabValue
	where ResultValue is not null
	group by LoincCode, LabUnits
	having count(*)>=10;


/*
-- Test queries
select top 100 * from AAFN_DiagnosisSummary order by NumberOfFacts desc;
select top 100 * from AAFN_MedicationSummary order by NumberOfFacts desc;
select top 100 * from AAFN_LabSummary order by NumberOfFacts desc;
select top 100 * from AAFN_LabValueSummary order by NumberOfNumericResults desc;
select top 100 *, count(*) over (partition by LoincCode) k from AAFN_LabValueSummary order by k desc, LoincCode;

-- Output results
select * from AAFN_DiagnosisSummary order by ICD10Code;
select * from AAFN_MedicationSummary order by RxNormCode;
select * from AAFN_LabSummary order by LoincCode;
select * from AAFN_LabValueSummary order by LoincCode,LabUnits;
*/

