Include Ensemble

Class MVP.EG.HIXNY.ADT.Operation Extends Ens.BusinessOperation [ StorageStrategy = "" ]
{

Property TargetConfigName As Ens.DataType.ConfigName [ InitialExpression = "HS.Gateway.SDA3.InboundProcess" ];

Property ControlID As %Integer;

Property ForceEligibilityAndMemberLoadForTest As %Boolean;

Parameter SETTINGS = "TargetConfigName,ForceEligibilityAndMemberLoadForTest";

Method LoadRequest(
	pRequest As MVP.EG.Load.Request,
	Output pResponse As Ens.Response) As %Status
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	#dim tStagedRecords As %SQL.StatementResult
	
	set tSC = $$$OK
	Try {

		#dim tCONTROLID As %String = pRequest.ControlID
		#dim tMRN As %String = $P(pRequest.DistinctValues, ",", 1)

		$$$TRACE("START:  CREATE SDA Container => MEMECK="_ tMRN)

	  	// If we are in test mode, we need to go load the coverage and 
	  	// member for the current MEME_CK since we can't assume it's already in HS
	  	if (..ForceEligibilityAndMemberLoadForTest)
	  	{		  	
	  		$$$THROWONERROR(tSC,..LoadMemberAndEligbilty(tMRN))			
	  	}	

		// Create SDA Container
       	set tContainer=##class(HS.SDA3.Container).%New()

		// Add Patient Data to SDA Container
		set tPatient=##class(HS.SDA3.Patient).%New()
		set tPatMRN=##class(HS.SDA3.PatientNumber).%New()
		set tPatMRN.Organization.Code="HIXNY"
		set tPatMRN.Number=tMRN
		set tPatMRN.NumberType="MRN"
		set tPatMRN.Organization.Code="MVP"
		set tPatMRN.ISOAssigningAuthority="MVP"
		DO tPatient.PatientNumbers.Insert(tPatMRN)

		// Intialize New Instance of Lab Order,  Add Test Results and theen add Lab Order to SDA3 Container
		set tEncounter = ##class(HS.SDA3.Encounter).%New()
		set tSC = ..AddAdtEncounterDataToSDA(pRequest,.tContainer,.tPatient,.tEncounter)	
		set tContainer.Patient=tPatient
		
		$$$ThrowOnError(tSC)

		set tQuickStream = ##class(%GlobalCharacterStream).%New()			
		$$$THROWONERROR(tSC,tContainer.ToQuickXMLStream(.tQuickStream))
		
		// Demographics is added through Member View (. This data already comes from the Member SQL View
		set tRequest=##class(HS.Message.ECRUpdateRequest).%New()
		set tRequest.StreamContentType="SDA3"
			
		$$$THROWONERROR(tSC, tRequest.ContentStream.CopyFrom(tQuickStream))		
		$$$THROWONERROR(tSC, ..SendRequestSync(..TargetConfigName,tRequest,.tResponse))
		do tQuickStream.Clear(1)

		$$$TRACE("END:  SEND SDA Container Complete => HS.Gateway.SDA3.InboundProcess:  MEMECK: " _ " - " _ tMRN)
	} 
	catch e 
	{
		s tSC = e.AsStatus()
		$$$LOGINFO(tSC)
	}

	#dim tAuditSC = ##class(MVP.EG.Load.Audit).Update(pRequest.ControlID,..%SessionId,tSC)

	Quit tSC
}

Method LoadMemberAndEligbilty(pMRN As %String)
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {		
	  	set tControlIDStatement = ##class(%SQL.Statement).%New()	  			  	
		$$$THROWONERROR(tSC, tControlIDStatement.%PrepareClassQuery("MVP.EG.Facets.Eligibility.Operation","GetEligibilityControlIDForMemeCK"))								
	  	#dim tControlResultSet=tControlIDStatement.%Execute(pMRN)			  		  	
        
        if tControlResultSet.%SQLCODE = 0 {
                        
            While tControlResultSet.%Next()	 
            {
	            set tEligibilityRequest=##class(MVP.EG.Load.Request).%New()
 				set tEligibilityRequest.ControlID = tControlResultSet.%Get("ID")							
 				set tEligibilityRequest.DistinctValueFields = "MEME_CK"
 				set tEligibilityRequest.DistinctValues = pMRN
				$$$THROWONERROR(tSC, ..SendRequestSync("Facets.Eligibility.Operation",tEligibilityRequest,.tResponse))				  	
            }			            
        } 														  	
	} 
	catch e 
	{
		s tSC = e.AsStatus()	
	}	
	Quit tSC
}

/*
	Add Lab Test Results to Lab Order and then Update SDA
*/
Method AddAdtEncounterDataToSDA(
	pRequest As MVP.EG.Load.Request,
	ByRef tContainer As HS.SDA3.Container,
	ByRef tPatient As HS.SDA3.PatientNumber,
	ByRef tEncounter As HS.SDA3.Encounter) As %Status
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	#dim resultset As %SQL.StatementResult
	try 
	{  		
		Set tSC = ..GetStagedRecords(pRequest,.resultset)
		$$$ThrowOnError(tSC)
		
	  	#dim actionCode as %String
	  	#dim bValidateHeader as %Boolean = 0
		#dim nCounter as %Integer = 0
		
		While resultset.%Next() 
		{
			#dim FILEIDENT As %String = $ZSTRIP(resultset."FILE_IDENT","<>WC")
			#dim MRN As %String = $ZSTRIP(resultset."MRN","<>WC")
			#dim MEMBERID As %String = $ZSTRIP(resultset."MVP_MEMBER_ID","<>WC")
			#dim MPIID As %String = $ZSTRIP(resultset."MPIID","<>WC")
			#dim AACODE As %String = $ZSTRIP($ZSTRIP(resultset."AA_CODE","<>WC"), "*P")
			#dim ASSIGNINGAUTHORITY As %String = $ZSTRIP(resultset."ASSIGNING_AUTHORITY","<>WC")
			#dim PATIENTFIRSTNAME As %String = $ZSTRIP(resultset."PATIENT_FIRST_NAME","<>WC")
			#dim PATIENTLASTNAME As %String = $ZSTRIP(resultset."PATIENT_LAST_NAME","<>WC")
			#dim PATIENTMIDDLEINITIAL As %String = $ZSTRIP(resultset."PATIENT_MIDDLE_INITIAL","<>WC")
			#dim SEX As %String = $ZSTRIP(resultset."SEX","<>WC")
			// AGE - skipped
			#dim BIRTHDATE As %String = $ZSTRIP(resultset."BIRTH_DATE","<>WC")
			#dim HOMEPHONE As %String = $ZSTRIP(resultset."HOME_PHONE","<>WC")
			#dim ARRIVALDATETIME As %String = ##class(HS.Gateway.HL7.HL7ToSDA3).xmltimestamp($ZSTRIP(resultset."ARRIVAL_DATE_TIME","<>WC"))
			#dim DEPARTERDATETIME As %String = ##class(HS.Gateway.HL7.HL7ToSDA3).xmltimestamp($ZSTRIP(resultset."DEPART_ER_DATE_TIME","<>WC"))
			#dim MESSAGEDATETIME As %String = ##class(HS.Gateway.HL7.HL7ToSDA3).xmltimestamp($ZSTRIP(resultset."MESSAGE_DATE_TIME","<>WC"))
			#dim DISPOSITIONDISCHARGEDIAGNOSIS As %String = $ZSTRIP(resultset."DISPOSITION_DISCHARGE_DIAGNOSIS","<>WC")
			#dim CHIEFCOMPLAINT As %String = $ZSTRIP(resultset."CHIEF_COMPLAINT","<>WC")
			#dim DISCHARGEDISPOSITION As %String = $ZSTRIP(resultset."DISCHARGE_DISPOSITION","<>WC")
			#dim DISCHARGEDTOLOCATION As %String = $ZSTRIP(resultset."DISCHARGED_TO_LOCATION","<>WC")
			#dim PRIMARYINSURANCE As %String = $ZSTRIP(resultset."PRIMARYINSURANCE","<>WC")
			#dim INSURANCEPOLICY As %String = $ZSTRIP(resultset."INSURANCE_POLICY","<>WC")			
			#dim PRIMARYCAREPHYSICIAN As %String = $ZSTRIP(resultset."PRIMARY_CARE_PHYSICIAN","<>WC")
			#dim EVENTTYPE As %String = $ZSTRIP(resultset."EVENT_TYPE","<>WC")
			#dim ENCOUNTERTYPE As %String = $ZSTRIP(resultset."ENCOUNTER_TYPE","<>WC")
			#dim STGRECSTATUS As %String = $ZSTRIP(resultset."STG_REC_STATUS","<>WC")
			#dim STGRECLOADDATE As %String = ##class(HS.Gateway.HL7.HL7ToSDA3).xmltimestamp($ZSTRIP(resultset."STG_REC_LOADDATE","<>WC"))

			//Implement SDA mapping
			if bValidateHeader = 0 
			{
				set tPatMB=##class(HS.SDA3.PatientNumber).%New()
				set tPatMB.Organization.Code="HIXNY"
				set tPatMB.Number=MEMBERID
				set tPatMB.NumberType="MB"
				set tPatMB.Organization.Code="MVP"
				set tPatMB.ISOAssigningAuthority="MVP"
				DO tPatient.PatientNumbers.Insert(tPatMB)            	

				set tPatMB=##class(HS.SDA3.PatientNumber).%New()
				set tPatMB.Organization.Code="HIXNY"
				set tPatMB.Number=MPIID
				set tPatMB.NumberType="MPI"
				set tPatMB.Organization.Code="MVP"
				set tPatMB.ISOAssigningAuthority="MVP"
				DO tPatient.PatientNumbers.Insert(tPatMB)   

				// Map Patient Data
			  	set tPatient.Name.FamilyName=PATIENTLASTNAME
			  	set tPatient.Name.GivenName=PATIENTFIRSTNAME
			  	set tPatient.Name.MiddleName=PATIENTMIDDLEINITIAL
			  	set tPatient.Gender.Code=SEX
			  	set tPatient.Gender.SDACodingStandard = ##class(HS.Data.OIDMap).GetURLForCode("AdministrativeGender")
				set tPatient.ContactInfo.HomePhoneNumber=HOMEPHONE
				set tPatient.BirthTime=BIRTHDATE

				set bValidateHeader = 1  
			}

			set tEncounter = ##class(HS.SDA3.Encounter).%New()

 			set tEncounter.EncounterType = ENCOUNTERTYPE
			set tEncounter.EncounterNumber = $System.Util.CreateGUID()
			set tEncounter.EncounterMRN=MRN
			set tEncounter.FromTime=ARRIVALDATETIME
			set tEncounter.ToTime=DEPARTERDATETIME
			set tEncounter.EmergencyAdmitDateTime=ARRIVALDATETIME

			// Add Primary Care Provider
			set tCareProvider = ##class(HS.SDA3.CodeTableDetail.CareProvider).%New()
			set tCareProvider.Name.FamilyName=PRIMARYCAREPHYSICIAN
			set tCareProvider.Name.GivenName=PRIMARYCAREPHYSICIAN
			do tEncounter.AttendingClinicians.Insert(tCareProvider)			

			// Assigning Authority Code 			
			set tContainer.SendingFacility=AACODE  

			// Add Encoutner to SDA Container
			do tContainer.Encounters.Insert(tEncounter)
			
			// Increment FOR..LOOP counter
			set nCounter = $I(nCounter)
		}
		$$$ThrowOnError(tSC)
		
		Write !, "HIXNY ADT - Complete Adding Encounter", !
	}
	catch e 
	{
		set tSC = e.AsStatus()
		$$$LOGINFO(tSC)
	}
	quit tSC
}

// GET LAB TEST RSULTS RECORDS FROM STAGING TABLE

Method GetStagedRecords(
	pRequest As MVP.EG.Load.Request,
	ByRef pRecordResult As %SQL.StatementResult) As %Status
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	Try 
	{
		#dim tControl = ##class(MVP.EG.Load.Control).%OpenId(pRequest.ControlID)
		
		#dim tConfig = ##class(MVP.EG.Load.Configuration).GetConfig(tControl.InterfaceName)
		#dim tTablename = $TR($P(tConfig.StagingTableClass,".",1,($LENGTH(tConfig.StagingTableClass,".")-1)),".","_")_"."_$P(tConfig.StagingTableClass,".",*)

		#dim tDistinctFieldsList = $LFS(pRequest.DistinctValueFields)
		#dim tDistinctValuesList = $LFS(pRequest.DistinctValues)
		#dim tSQL As %String
		
		Set tSQL($I(tSQL)) = "SELECT *"
		Set tSQL($I(tSQL)) = "FROM "_tTablename
		Set tSQL($I(tSQL)) = "WHERE "_tConfig.GroupBy1_" = '"_tControl.GroupBy1_"'"
		Set:tConfig.GroupBy2'="" tSQL($I(tSQL)) = "AND "_tConfig.GroupBy2_" = '"_tControl.GroupBy2_"'"
		Set:tConfig.GroupBy3'="" tSQL($I(tSQL)) = "AND "_tConfig.GroupBy3_" = '"_tControl.GroupBy3_"'"
		Set:tConfig.GroupBy4'="" tSQL($I(tSQL)) = "AND "_tConfig.GroupBy4_" = '"_tControl.GroupBy4_"'"
		Set:tConfig.GroupBy5'="" tSQL($I(tSQL)) = "AND "_tConfig.GroupBy5_" = '"_tControl.GroupBy5_"'"
		
		#dim fieldCounter As %Integer
		For fieldCounter=1:1:$LL(tDistinctFieldsList) 
		{
			// if $LI(tDistinctValuesList,i) = "" CONTINUE
			if $LI(tDistinctValuesList,fieldCounter) '= "" {
				Set tSQL($I(tSQL)) = "AND "_$LI(tDistinctFieldsList,fieldCounter)_" = '"_$LI(tDistinctValuesList,fieldCounter)_"'"
			}
			else {
				Set tSQL($I(tSQL)) = "AND "_$LI(tDistinctFieldsList,fieldCounter)_" IS NULL"				
			}
		}

		Set tSQLStatement = ##class(%SQL.Statement).%New()
		Set tSC = tSQLStatement.%Prepare(.tSQL)
		$$$ThrowOnError(tSC)
		
		Set pRecordResult = tSQLStatement.%Execute()
		If pRecordResult.%SQLCODE < 0 
		{
			#dim ec = ##class(%Exception.SQL).CreateFromSQLCODE(pRecordResult.%SQLCODE, pRecordResult.%Message)
			throw ec
		}
	} 
	catch e 
	{
		s tSC = e.AsStatus()
	}
	Quit tSC
}

// Set ClassMethod as the DEBUG TARGE 

ClassMethod TestBusinessProcess() As %Status
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	Try 
	{
		set tRequest=##class(MVP.EG.Load.Request).%New()
		set tRequest.ControlID = "9928"
		set tRequest.DistinctValueFields = "MRN"
		set tRequest.DistinctValues = "0012612107"  

		#dim tProcess=##class(Ens.Host).GetShadowInstance("HIXNY.Encounter.Operation")

		do tProcess.OnInit()

		set tSC = tProcess.OnRequest(tRequest,.tResponse)		
	} 
	catch e 
	{
		s tSC = e.AsStatus()
	}
	Quit tSC
}

XData MessageMap
{
<MapItems>
	<MapItem MessageType="MVP.EG.Load.Request"> 
		<Method>LoadRequest</Method>
	</MapItem>
</MapItems>
}

/// Revision number of this class
Parameter SrcVer = 11;

}
