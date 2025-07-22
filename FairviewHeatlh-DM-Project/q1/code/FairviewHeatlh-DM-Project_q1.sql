;with Diagnosis as (
    -- Point to your database table containing ICD-10 diagnosis codes
    select patient_num as PatientNum, 
        concept_cd as ICD10Code, 
        start_date as DiagnosisDate
    from crc.observation_fact
), PatientDiagnosisDates as (
    -- Remove the 'ICD10CM:' prefix if needed
    select PatientNum, 
        ICD10Code, 
        count(distinct cast(DiagnosisDate as date)) NumDates
    from Diagnosis
    where ICD10Code like 'ICD10CM:E0[89]%' 
        or ICD10Code like 'ICD10CM:E1[13]%'
    group by ICD10Code, PatientNum
), DiagnosisCounts as (
    -- Calculate counts for each diagnosis code
    select ICD10Code,
        count(*) NumberOfPatients,
        sum(case when NumDates>=2 
            then 1 
            else 0 end) PatientsWithTwoPlusDiagDates
    from PatientDiagnosisDates
    group by ICD10Code
)
-- Mask small counts less than 10
select ICD10Code, 
    NumberOfPatients, 
    (case when PatientsWithTwoPlusDiagDates>=10 
        then PatientsWithTwoPlusDiagDates 
        else -1 end) PatientsWithTwoPlusDiagDates
from DiagnosisCounts
where NumberOfPatients>=10
order by ICD10Code;
