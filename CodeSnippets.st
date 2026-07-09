IP_SEW_GTW:				STRING	:= '10.150.2.4';

awWriteDataSEW_FU					: ARRAY [0..124] OF WORD;	
FC_SEW_ModbusWrite                  : ARRAY[0..7,0..2] OF WORD;
FC_SEW_ModbusRead                   : ARRAY[0..7,0..2] OF WORD;


//###################################################
	

Memcopy(ADR(awWriteDataSEW_FU), ADR(FC_SEW_ModbusWrite), SIZEOF(FC_SEW_ModbusWrite));
Mod_SEW_FU(	bUnitId				:= 16#00,
            bFunctionCode		:= 16#17,
            uiReadAddress		:= 16#4,
            uiReadQuantity		:= 24,
            uiWriteAddress		:= 16#4,
            uiWriteQuantity		:= 24,
            IP					:= SystemParameter.IP_SEW_GTW,
            ResetTime			:= T#2S,
            tTimeOut			:= T#200MS,
            wPort				:= 502,
            RequestGapTime		:= T#30MS,
            awReadData			:= awReadDataSEW_FU,
            awWriteData			:= awWriteDataSEW_FU);
Memcopy(ADR(FC_SEW_ModbusRead), ADR(awReadDataSEW_FU), SIZEOF(FC_SEW_ModbusWrite));

//###################################################
	


(* forward speed *)
IF SysVar.TeachSpeedInProgress AND IN.RCU_WashLineIndicator_ THEN
	FC_MasterWrite.SetPointRPM := SysVar.TeachSpeedRPM;
ELSE
	FC_MasterWrite.SetPointRPM := SysVar.FC_DriveSetpointRPM;
END_IF

(* rotation direction *)
IF NOT CustomerParameter.RotationDirection THEN
	FC_MasterWrite.SetPointRPM := FC_MasterWrite.SetPointRPM * -1;
END_IF

(* manage output stage enable *)
IF	FC_MasterWrite.SetPointRPM <> 0 THEN
	FC_MasterWrite.Enable	:= TRUE;
ELSIF SM_RotaryControl.runtime > T#30s THEN
	FC_MasterWrite.Enable	:= FALSE;
END_IF


(* Forward Ramp Time *)
FC_MasterWrite.RampTimeStart := SysVar.FC_RampTime;
FC_MasterWrite.RampTimeStop	 := SysVar.FC_RampTime;

ToogleCommuncationTimer(Enable := TRUE, TIMELOW := T#200MS, TIMEHIGH := T#200MS);
IF ToogleCommuncationTimer.OUT THEN
	CommunicationActive := TRUE;
ELSE
	CommunicationActive := FALSE;
END_IF

// Check if one FC is switched of ... then
ParlourControlManual := FALSE;
SchneiderFCDetected := FALSE;
FOR i := 0 TO CustomerParameter.NrOfDrives-1 DO
	IF FC_MasterRead[i].Manual THEN
		ParlourControlManual := TRUE;
	END_IF
		
	IF Modbus.Mod_SchneiderFU[i].xIsOpen THEN
		SchneiderFCDetected := TRUE;
	END_IF	
END_FOR

IF  Modbus.Mod_SchneiderFU[enum_VFD_Function.GM1].xIsOpen OR Modbus.Mod_SchneiderFU[enum_VFD_Function.GM2].xIsOpen THEN
		SchneiderMLDetected := TRUE;
END_IF

IF  Modbus.Mod_SchneiderFU[enum_VFD_Function.DL1].xIsOpen OR Modbus.Mod_SchneiderFU[enum_VFD_Function.DL2].xIsOpen THEN
		SchneiderDLDetected := TRUE;
END_IF	

IF  Modbus.Mod_SchneiderFU[enum_VFD_Function.MWR].xIsOpen THEN
		SchneiderMWRDetected := TRUE;
END_IF	

IF NOT SchneiderFCDetected THEN
	IF NOT Modbus.Mod_SEW_FU.xIsOpen THEN
		ParlourControlManual := TRUE;
	END_IF
END_IF

IF NOT Modbus.ModOCU.xIsOpen THEN
	ParlourControlManual := TRUE;
END_IF
	
IF ParlourControlManual THEN
	FC_MasterWrite.RampTimeStart := 3000;
	FC_MasterWrite.RampTimeStop := 1000;
END_IF



(* cpy data to Schneider FC*)
FOR i:=0 TO enum_VFD_Function.Drive10 BY 1 DO
	FC_SchneiderWrite[i].ControlBit_Run			:= FC_MasterWrite.Enable;
	FC_SchneiderWrite[i].ControlBit_RunReverse	:= FALSE;						(* controlled by integer setpoint *)
	FC_SchneiderWrite[i].ControlBit_FaultReset	:= FC_MasterWrite.ErrorReset;
	FC_SchneiderWrite[i].ControlBit_Reserve0	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_Reserve01	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_Reserve02	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_Reserve03	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_Reserve04	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_Reserve05	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_Reserve06	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_Reserve07	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_OverrideMWR	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_Reserve09	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_Reserve10	:= FALSE;
	FC_SchneiderWrite[i].CommunicationActive	:= CommunicationActive;
	FC_SchneiderWrite[i].ControlBit_Reserve12	:= StartAutomatic;

	(* allocate bits to ctrl word *)
	FC_SchneiderWrite[i].ControlWord.0			:= FC_SchneiderWrite[i].ControlBit_Run;
	FC_SchneiderWrite[i].ControlWord.1			:= FC_SchneiderWrite[i].ControlBit_RunReverse;
	FC_SchneiderWrite[i].ControlWord.2			:= FC_SchneiderWrite[i].ControlBit_FaultReset;
	FC_SchneiderWrite[i].ControlWord.3			:= FC_SchneiderWrite[i].ControlBit_Reserve0;
	FC_SchneiderWrite[i].ControlWord.4			:= FC_SchneiderWrite[i].ControlBit_Reserve01;
	FC_SchneiderWrite[i].ControlWord.5			:= FC_SchneiderWrite[i].ControlBit_Reserve02;
	FC_SchneiderWrite[i].ControlWord.6			:= FC_SchneiderWrite[i].ControlBit_Reserve03;
	FC_SchneiderWrite[i].ControlWord.7			:= FC_SchneiderWrite[i].ControlBit_Reserve04;
	FC_SchneiderWrite[i].ControlWord.8			:= FC_SchneiderWrite[i].ControlBit_Reserve05;
	FC_SchneiderWrite[i].ControlWord.9			:= FC_SchneiderWrite[i].ControlBit_Reserve06;
	FC_SchneiderWrite[i].ControlWord.10			:= FC_SchneiderWrite[i].ControlBit_Reserve07;
	FC_SchneiderWrite[i].ControlWord.11			:= FC_SchneiderWrite[i].ControlBit_OverrideMWR;
	FC_SchneiderWrite[i].ControlWord.12			:= FC_SchneiderWrite[i].ControlBit_Reserve09;
	FC_SchneiderWrite[i].ControlWord.13			:= FC_SchneiderWrite[i].ControlBit_Reserve10;
	FC_SchneiderWrite[i].ControlWord.14			:= FC_SchneiderWrite[i].CommunicationActive;
	FC_SchneiderWrite[i].ControlWord.15			:= FC_SchneiderWrite[i].ControlBit_Reserve12;

	FC_SchneiderWrite[i].SetPointRPM			:= FC_MasterWrite.SetPointRPM;
	FC_SchneiderWrite[i].RampTimeStart			:= FC_MasterWrite.RampTimeStart / 100;
	FC_SchneiderWrite[i].RampTimeStop			:= FC_MasterWrite.RampTimeStop / 100;
	FC_SchneiderWrite[i].Out_4_20mA				:= 0;
	FC_SchneiderWrite[i].Reserve01				:= 0;
	FC_SchneiderWrite[i].Reserve02				:= 0;
	FC_SchneiderWrite[i].Reserve03				:= 0;
END_FOR;

(* cpy data to SEW FC*)
FOR i:=0 TO 5 BY 1 DO
	FC_SEW_Write[i].ControlWord.0 	:= FALSE;						(* ControlerInhibit *)
	FC_SEW_Write[i].ControlWord.1	:= FC_MasterWrite.Enable;		(* NoRapidStop *)
	FC_SEW_Write[i].ControlWord.2	:= FC_MasterWrite.Enable;		(* Enable *)
	FC_SEW_Write[i].ControlWord.3	:= FALSE;						(* HoldControl *)
	FC_SEW_Write[i].ControlWord.4	:= FALSE;						(* IntegratorSwitchover *)
	FC_SEW_Write[i].ControlWord.5	:= FALSE;						(* ParameterSetSwitchover *)
	FC_SEW_Write[i].ControlWord.6	:= FC_MasterWrite.ErrorReset;	(* Reset *)
	FC_SEW_Write[i].ControlWord.7	:= FALSE;						(* Reserved0 *)
	FC_SEW_Write[i].ControlWord.8	:= FALSE;						(* DirectionMotorPotent *)
	FC_SEW_Write[i].ControlWord.9	:= FALSE;						(* MotorPotentAccBit0 *)
	FC_SEW_Write[i].ControlWord.10	:= FALSE;						(* MotorPotentAccBit1 *)
	FC_SEW_Write[i].ControlWord.11	:= FALSE;						(* ParameterSelectionBit0 *)
	FC_SEW_Write[i].ControlWord.12	:= FALSE;						(* ParameterSelectionBit1 *)
	FC_SEW_Write[i].ControlWord.13	:= FALSE;						(* SetpointSwitchover *)
	FC_SEW_Write[i].ControlWord.14	:= FALSE;						(* Reserved1 *)
	FC_SEW_Write[i].ControlWord.15	:= FALSE;						(* Reserved2 *)

	FC_SEW_Write[i].SetPointRPM := FC_MasterWrite.SetPointRPM * 5;
	FC_SEW_Write[i].RampTime 	:= FC_MasterWrite.RampTimeStart * 2;
END_FOR;

(* allocate to modbus struct *)
FC_SEW_ModbusWrite[0,0] := FC_SEW_Write[0].ControlWord;
FC_SEW_ModbusWrite[0,1] := FC_SEW_Write[0].SetPointRPM;
FC_SEW_ModbusWrite[0,2] := FC_SEW_Write[0].RampTime;
FC_SEW_ModbusWrite[1,0] := FC_SEW_Write[1].ControlWord;
FC_SEW_ModbusWrite[1,1] := FC_SEW_Write[1].SetPointRPM;
FC_SEW_ModbusWrite[1,2] := FC_SEW_Write[1].RampTime;
FC_SEW_ModbusWrite[2,0] := FC_SEW_Write[2].ControlWord;
FC_SEW_ModbusWrite[2,1] := FC_SEW_Write[2].SetPointRPM;
FC_SEW_ModbusWrite[2,2] := FC_SEW_Write[2].RampTime;
FC_SEW_ModbusWrite[3,0] := FC_SEW_Write[3].ControlWord;
FC_SEW_ModbusWrite[3,1] := FC_SEW_Write[3].SetPointRPM;
FC_SEW_ModbusWrite[3,2] := FC_SEW_Write[3].RampTime;
FC_SEW_ModbusWrite[4,0] := FC_SEW_Write[4].ControlWord;
FC_SEW_ModbusWrite[4,1] := FC_SEW_Write[4].SetPointRPM;
FC_SEW_ModbusWrite[4,2] := FC_SEW_Write[4].RampTime;
FC_SEW_ModbusWrite[5,0] := FC_SEW_Write[5].ControlWord;
FC_SEW_ModbusWrite[5,1] := FC_SEW_Write[5].SetPointRPM;
FC_SEW_ModbusWrite[5,2] := FC_SEW_Write[5].RampTime;

FOR i:=enum_VFD_Function.MWR TO enum_VFD_Function.DL2 BY 1 DO	
	FC_SchneiderWrite[i].ControlBit_RunReverse	:= FALSE;											(* controlled by integer setpoint *)
	FC_SchneiderWrite[i].ControlBit_FaultReset	:= FC_SchneiderWrite[i].SetPointRPM > 0;			//FC_MasterWrite.ErrorReset;
	FC_SchneiderWrite[i].ControlBit_Reserve0	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_Reserve01	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_Reserve02	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_Reserve03	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_Reserve04	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_Reserve05	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_Reserve06	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_Reserve07	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_OverrideMWR	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_Reserve09	:= FALSE;
	FC_SchneiderWrite[i].ControlBit_Reserve10	:= FALSE;
	FC_SchneiderWrite[i].CommunicationActive	:= CommunicationActive;
	FC_SchneiderWrite[i].ControlBit_Reserve12	:= StartAutomatic;

	(* allocate bits to ctrl word *)	
	FC_SchneiderWrite[i].ControlWord.1			:= FC_SchneiderWrite[i].ControlBit_RunReverse;
	FC_SchneiderWrite[i].ControlWord.2			:= FC_SchneiderWrite[i].ControlBit_FaultReset;
	FC_SchneiderWrite[i].ControlWord.3			:= FC_SchneiderWrite[i].ControlBit_Reserve0;
	FC_SchneiderWrite[i].ControlWord.4			:= FC_SchneiderWrite[i].ControlBit_Reserve01;
	FC_SchneiderWrite[i].ControlWord.5			:= FC_SchneiderWrite[i].ControlBit_Reserve02;
	FC_SchneiderWrite[i].ControlWord.6			:= FC_SchneiderWrite[i].ControlBit_Reserve03;
	FC_SchneiderWrite[i].ControlWord.7			:= FC_SchneiderWrite[i].ControlBit_Reserve04;
	FC_SchneiderWrite[i].ControlWord.8			:= FC_SchneiderWrite[i].ControlBit_Reserve05;
	FC_SchneiderWrite[i].ControlWord.9			:= FC_SchneiderWrite[i].ControlBit_Reserve06;
	FC_SchneiderWrite[i].ControlWord.10			:= FC_SchneiderWrite[i].ControlBit_Reserve07;
	FC_SchneiderWrite[i].ControlWord.11			:= FC_SchneiderWrite[i].ControlBit_OverrideMWR;
	FC_SchneiderWrite[i].ControlWord.12			:= FC_SchneiderWrite[i].ControlBit_Reserve09;
	FC_SchneiderWrite[i].ControlWord.13			:= FC_SchneiderWrite[i].ControlBit_Reserve10;
	FC_SchneiderWrite[i].ControlWord.14			:= FC_SchneiderWrite[i].CommunicationActive;
	FC_SchneiderWrite[i].ControlWord.15			:= FC_SchneiderWrite[i].ControlBit_Reserve12;
	
	IF i = enum_VFD_Function.MWR THEN	// MWR		
		// Get different channels -> Only one channel should be connected
		IF FC_SchneiderRead[i].In4_20mA > 0 THEN
			LevelTemp := WORD_TO_REAL(FC_SchneiderRead[i].In4_20mA);			
		ELSIF FC_SchneiderRead[i].AnalogIn_0_10V >0 THEN
			LevelTemp := WORD_TO_REAL(FC_SchneiderRead[i].AnalogIn_0_10V);
		ELSE
			LevelTemp := 0;
		END_IF
		
		// Scale level to 0 ... 100
		LevelTemp := (LevelTemp*100)/8192;
		// Ignore LEvel Temp < 5
		IF LevelTemp < LevelSwitchMilkPumpOffsetZero_MWR THEN
			LevelTemp := 0;
		END_IF
		
		MilkPumpAnalog_MWR.CurrentLevel := REAL_TO_INT(LevelTemp);
		
		
		
		// Calculate Pump RPM
		//MilkPumpSetPoint := (3000/MilkPumpAnalog_MWR.SetPointMax)*LevelTemp;
		MilkPumpSetPoint := (MilkPumpAnalog_MWR.MaxRPM-MilkPumpAnalog_MWR.SetPointMin)/(MilkPumpAnalog_MWR.SetPointMax-LevelSwitchMilkPumpOffsetZero_MWR)*(LevelTemp-MilkPumpAnalog_MWR.SetPointMax)+MilkPumpAnalog_MWR.MaxRPM;
		IF MilkPumpSetPoint < MilkPumpAnalog_MWR.SetPointMin THEN
			MilkPumpSetPoint := 0;
		END_IF
		// Evaluate MilkPumpSetPoint for Washing/MWR
		IF IN.RCU_SystemWashing THEN
			IF OUT.RCU_SignalDrainKK THEN
				MilkPumpSetPoint := MilkPumpAnalog_MWR.MaxRPM;
			ELSE
				MilkPumpSetPoint := 0;
			END_IF	
		// Evaluate MilkPumpSetPoint for Milking/MWR	
		ELSIF  MilkPumpSetPoint > MilkPumpAnalog_MWR.MaxRPM OR FC_SchneiderRead[i].DigitalIn.14 THEN
			MilkPumpSetPoint := MilkPumpAnalog_MWR.MaxRPM;
		ELSIF MilkPumpSetPoint > 0 AND MilkPumpSetPoint < MilkPumpAnalog_MWR.SetPointMin AND NOT IN.RCU_SystemWashing THEN
			MilkPumpSetPoint := MilkPumpAnalog_MWR.SetPointMin;
		ELSIF MilkPumpSetPoint = 0 THEN
			IF DelayTimer[i-enum_VFD_Function.MWR].Q THEN
				MilkPumpSetPoint := MilkPumpAnalog_MWR.SetPointMin;
			ELSE
				MilkPumpSetPoint := 0;
			END_IF
		END_IF
		
		DelayTimer[i-enum_VFD_Function.MWR](IN:=LevelTemp>0, PT:=INT_TO_TIME(1000*MilkPumpAnalog_MWR.SwitchOffDelay));
		
		IF Washer.FDA_Error OR WWT_PRG.WWT.Errors.VacuumOffMWROff THEN
			MilkPumpSetPoint := 0;
		END_IF
		
	ELSE 	

		// Centre MPs
	
		// Softstart. In case of level controlled SetPoint is overwritten.		
		SoftstartTimer[i-enum_VFD_Function.GM1](IN := FC_SchneiderRead[i].DigitalIn.14, PT:=INT_TO_TIME(1000*MilkPumpAnalog_Centre.SwitchOffDelay));
		
		IF SoftstartTimer[i-enum_VFD_Function.GM1].Q THEN
			MilkPumpSetPoint := MilkPumpAnalog_Centre.MaxRPM;
		ELSE
			MilkPumpSetPoint := 0;
		END_IF
			
		// Override digital mechaism if anaolog in
		IF NOT SoftstartTimer[i-enum_VFD_Function.GM1].Q THEN	
			// Get different channels -> Only one channel should be connected
			IF FC_SchneiderRead[i].In4_20mA > 0 THEN
				LevelTemp := WORD_TO_REAL(FC_SchneiderRead[i].In4_20mA);			
			ELSIF FC_SchneiderRead[i].AnalogIn_0_10V >0 THEN
				LevelTemp := WORD_TO_REAL(FC_SchneiderRead[i].AnalogIn_0_10V);
			ELSE
				LevelTemp := 0;
			END_IF
			
			// Scale level to 0 ... 100
			LevelTemp := (LevelTemp*100)/8192;
			// Ignore LEvel Temp < 5
			IF LevelTemp < LevelSwitchMilkPumpOffsetZero_MPC THEN
				LevelTemp := 0;
			END_IF
			
			IF i = enum_VFD_Function.GM1 THEN
				MilkPumpAnalog_Centre_CurrentLevel_Real_1 := LevelTemp;
			END_IF
			
			IF i = enum_VFD_Function.GM2 THEN
				MilkPumpAnalog_Centre_CurrentLevel_Real_2 := LevelTemp;
			END_IF
			
			
			
			// Calculate Pump RPM
			//MilkPumpSetPoint := (3000/MilkPumpAnalog_Centre.SetPointMax)*LevelTemp;
			MilkPumpSetPoint := (MilkPumpAnalog_Centre.MaxRPM-MilkPumpAnalog_Centre.SetPointMin)/(MilkPumpAnalog_Centre.SetPointMax-LevelSwitchMilkPumpOffsetZero_MPC)*(LevelTemp-MilkPumpAnalog_Centre.SetPointMax)+MilkPumpAnalog_Centre.MaxRPM;
			IF MilkPumpSetPoint < MilkPumpAnalog_Centre.SetPointMin THEN
				MilkPumpSetPoint := 0;
			END_IF
			
			MilkPumpAnalog_Centre.CurrentLevel := REAL_TO_INT(LevelTemp);
			
			// Split generic level to dedicated milk pumps
			IF i = enum_VFD_Function.GM1 THEN
				MilkPumpAnalog_Centre_CurrentLevel_1 := MilkPumpAnalog_Centre.CurrentLevel;
			END_IF
			
			IF i = enum_VFD_Function.GM2 THEN
				MilkPumpAnalog_Centre_CurrentLevel_2 := MilkPumpAnalog_Centre.CurrentLevel;
			END_IF
				

						
			// Evaluate Limits				// Wash Mode for 
			IF MilkPumpSetPoint > MilkPumpAnalog_Centre.MaxRPM OR (IN.RCU_SystemWashing AND MilkPumpSetPoint > LevelSwitchMilkPumpOffsetZero_MPC) THEN
				MilkPumpSetPoint := MilkPumpAnalog_Centre.MaxRPM;
			ELSIF MilkPumpSetPoint > 0 AND MilkPumpSetPoint < MilkPumpAnalog_Centre.SetPointMin THEN
				MilkPumpSetPoint := MilkPumpAnalog_Centre.SetPointMin;
			ELSIF MilkPumpSetPoint = 0 THEN
				IF DelayTimer[i-enum_VFD_Function.MWR].Q THEN
					IF IN.RCU_SystemWashing THEN
						MilkPumpSetPoint :=MilkPumpAnalog_Centre.MaxRPM;
					ELSE
						MilkPumpSetPoint := MilkPumpAnalog_Centre.SetPointMin;
					END_IF
					
				ELSE
					MilkPumpSetPoint := 0;
				END_IF
			END_IF
		
			DelayTimer[i-enum_VFD_Function.MWR](IN:=LevelTemp>0, PT:=INT_TO_TIME(1000*MilkPumpAnalog_Centre.SwitchOffDelay));
		END_IF		
		
		
	END_IF	
	
	// Old Behaviour Restabbpumpen
	IF (Allocator_IO.visuOUT.CCU_PumpReciever1.Value OR OUT.CCU_PumpReciever1) AND i = enum_VFD_Function.GM1 THEN
			MilkPumpSetPoint := MilkPumpAnalog_Centre.MaxRPM;
	END_IF
	
	IF (Allocator_IO.visuOUT.CCU_PumpReciever2.Value OR OUT.CCU_PumpReciever2) AND i = enum_VFD_Function.GM2 THEN
			MilkPumpSetPoint := MilkPumpAnalog_Centre.MaxRPM;
	END_IF
	
	IF (Allocator_IO.visuOUT.CCU_PumpReciever3.Value OR OUT.CCU_PumpReciever3) AND i = enum_VFD_Function.DL1 THEN
			MilkPumpSetPoint := DumpLinePumpAnalog_Centre.MaxRPM;
	END_IF
	
	IF (Allocator_IO.visuOUT.CCU_PumpReciever4.Value OR OUT.CCU_PumpReciever4) AND i = enum_VFD_Function.DL2 THEN
			MilkPumpSetPoint := DumpLinePumpAnalog_Centre.MaxRPM;
	END_IF	
	
	IF ((Allocator_IO.visuOUT.RCU_SignalDrainKK.Value OR OUT.RCU_SignalDrainKK) AND i = enum_VFD_Function.MWR) OR (FC_SchneiderRead[enum_VFD_Function.MWR].DigitalIn.14 AND i = 8) THEN
			MilkPumpSetPoint := MilkPumpAnalog_MWR.MaxRPM;
	END_IF
					
	IF Washer.FDA_Error OR WWT_PRG.WWT.Errors.VacuumOffMWROff THEN
		MilkPumpSetPoint := 0;
	END_IF
		
	FC_SchneiderWrite[i].ControlWord.0			:= MilkPumpSetPoint > 0;
	FC_SchneiderWrite[i].SetPointRPM	 		:= REAL_TO_INT(MilkPumpSetPoint);
	FC_SchneiderWrite[i].ControlBit_Run			:= MilkPumpSetPoint > 0;
	FC_SchneiderWrite[i].ControlWord.0			:= FC_SchneiderWrite[i].ControlBit_Run;
	
	FC_SchneiderWrite[i].RampTimeStart			:= 30;
	FC_SchneiderWrite[i].RampTimeStop			:= 30;
	FC_SchneiderWrite[i].Out_4_20mA				:= 0;
	FC_SchneiderWrite[i].Reserve01				:= 0;
	FC_SchneiderWrite[i].Reserve02				:= 0;
	FC_SchneiderWrite[i].Reserve03				:= 0;
END_FOR;

// Spare Part Communication Alive Message
FC_SchneiderWrite[enum_VFD_Function.Spare].CommunicationActive	:= CommunicationActive;
FC_SchneiderWrite[enum_VFD_Function.Spare].ControlWord.14		:= FC_SchneiderWrite[enum_VFD_Function.Spare].CommunicationActive;

// Limit parameters
IF MilkPumpAnalog_MWR.SetPointMin < 900 THEN
	MilkPumpAnalog_MWR.SetPointMin := 900;
ELSIF MilkPumpAnalog_MWR.SetPointMin > 2500 THEN
	MilkPumpAnalog_MWR.SetPointMin := 2500;	
END_IF

IF MilkPumpAnalog_MWR.SetPointMax > 100 THEN
	MilkPumpAnalog_MWR.SetPointMax := 100;
ELSIF MilkPumpAnalog_MWR.SetPointMax < 50 THEN
	MilkPumpAnalog_MWR.SetPointMax := 50;
END_IF

IF MilkPumpAnalog_MWR.SwitchOffDelay > 20 THEN
	MilkPumpAnalog_MWR.SwitchOffDelay := 20;
ELSIF MilkPumpAnalog_MWR.SwitchOffDelay < 2 THEN
	MilkPumpAnalog_MWR.SwitchOffDelay := 2;
END_IF

IF MilkPumpAnalog_Centre.SetPointMin < 500 THEN
	MilkPumpAnalog_Centre.SetPointMin := 500;
ELSIF MilkPumpAnalog_Centre.SetPointMin > 2500 THEN
	MilkPumpAnalog_Centre.SetPointMin := 2500;	
END_IF

IF MilkPumpAnalog_Centre.SetPointMax > 100 THEN
	MilkPumpAnalog_Centre.SetPointMax := 100;
ELSIF MilkPumpAnalog_Centre.SetPointMax < 50 THEN
	MilkPumpAnalog_Centre.SetPointMax := 50;
END_IF

IF MilkPumpAnalog_Centre.SwitchOffDelay > 15 THEN
	MilkPumpAnalog_Centre.SwitchOffDelay := 15;
ELSIF MilkPumpAnalog_Centre.SwitchOffDelay < 2 THEN
	MilkPumpAnalog_Centre.SwitchOffDelay := 2;
END_IF

IF DumpLinePumpAnalog_Centre.SetPointMin < 500 THEN
	DumpLinePumpAnalog_Centre.SetPointMin := 500;
ELSIF DumpLinePumpAnalog_Centre.SetPointMin > 2500 THEN
	DumpLinePumpAnalog_Centre.SetPointMin := 2500;	
END_IF

IF DumpLinePumpAnalog_Centre.SetPointMax > 100 THEN
	DumpLinePumpAnalog_Centre.SetPointMax := 100;
ELSIF DumpLinePumpAnalog_Centre.SetPointMax < 50 THEN
	DumpLinePumpAnalog_Centre.SetPointMax := 50;
END_IF

IF DumpLinePumpAnalog_Centre.SwitchOffDelay > 15 THEN
	DumpLinePumpAnalog_Centre.SwitchOffDelay := 15;
ELSIF DumpLinePumpAnalog_Centre.SwitchOffDelay < 2 THEN
	DumpLinePumpAnalog_Centre.SwitchOffDelay := 2;
END_IF



// #################################
(* Allocate Schneider StatusWord  / rest of the struct is been allocated directly via modbus maste*)
//SBV FOR i:=0 TO 8 BY 1 DO
FOR i:=0 TO MAX_NUMBER_VFD BY 1 DO
	FC_SchneiderRead[i].StatusBit_Ready 				:= FC_SchneiderRead[i].StatusWord.0;
	FC_SchneiderRead[i].StatusBit_SwitchedOn			:= FC_SchneiderRead[i].StatusWord.1;
	FC_SchneiderRead[i].StatusBit_OperationEnabled		:= FC_SchneiderRead[i].StatusWord.2;
	FC_SchneiderRead[i].StatusBit_Fault					:= FC_SchneiderRead[i].StatusWord.3;
	FC_SchneiderRead[i].StatusBit_VoltageEnabled		:= FC_SchneiderRead[i].StatusWord.4;
	FC_SchneiderRead[i].StatusBit_QuickStop 			:= FC_SchneiderRead[i].StatusWord.5;
	FC_SchneiderRead[i].StatusBit_SwitchedOnDisabled	:= FC_SchneiderRead[i].StatusWord.6;
	FC_SchneiderRead[i].StatusBit_Warning				:= FC_SchneiderRead[i].StatusWord.7;
	FC_SchneiderRead[i].StatusBit_Reserved				:= FC_SchneiderRead[i].StatusWord.8;
	FC_SchneiderRead[i].StatusBit_Remote				:= FC_SchneiderRead[i].StatusWord.9;
	FC_SchneiderRead[i].StatusBit_TargetReached			:= FC_SchneiderRead[i].StatusWord.10;
	FC_SchneiderRead[i].StatusBit_IntervalLimitActive	:= FC_SchneiderRead[i].StatusWord.11;
	FC_SchneiderRead[i].StatusBit_Reserved01			:= FC_SchneiderRead[i].StatusWord.12;
	FC_SchneiderRead[i].StatusBit_Reserved02			:= FC_SchneiderRead[i].StatusWord.13;
	FC_SchneiderRead[i].StatusBit_StopViaKey			:= FC_SchneiderRead[i].StatusWord.14;
	FC_SchneiderRead[i].StatusBit_RotationDirection		:= FC_SchneiderRead[i].StatusWord.15;
END_FOR
// Spare Part FU
	FC_SchneiderRead[enum_VFD_Function.Spare].StatusBit_Ready 				:= FC_SchneiderRead[13].StatusWord.0;
	FC_SchneiderRead[enum_VFD_Function.Spare].StatusBit_Fault				:= FC_SchneiderRead[13].StatusWord.3;
	
(* Allocate FC_SEW_ModbusRead -> FC_SEW_Read *)
FC_SEW_Read[0].StatusWord	 	:= FC_SEW_ModbusRead[0,0];
FC_SEW_Read[0].OutputCurrent	:= FC_SEW_ModbusRead[0,1];
FC_SEW_Read[0].DriveRPM			:= FC_SEW_ModbusRead[0,2];
FC_SEW_Read[1].StatusWord	 	:= FC_SEW_ModbusRead[1,0];
FC_SEW_Read[1].OutputCurrent	:= FC_SEW_ModbusRead[1,1];
FC_SEW_Read[1].DriveRPM			:= FC_SEW_ModbusRead[1,2];
FC_SEW_Read[2].StatusWord	 	:= FC_SEW_ModbusRead[2,0];
FC_SEW_Read[2].OutputCurrent	:= FC_SEW_ModbusRead[2,1];
FC_SEW_Read[2].DriveRPM			:= FC_SEW_ModbusRead[2,2];
FC_SEW_Read[3].StatusWord	 	:= FC_SEW_ModbusRead[3,0];
FC_SEW_Read[3].OutputCurrent	:= FC_SEW_ModbusRead[3,1];
FC_SEW_Read[3].DriveRPM			:= FC_SEW_ModbusRead[3,2];
FC_SEW_Read[4].StatusWord	 	:= FC_SEW_ModbusRead[4,0];
FC_SEW_Read[4].OutputCurrent	:= FC_SEW_ModbusRead[4,1];
FC_SEW_Read[4].DriveRPM			:= FC_SEW_ModbusRead[4,2];
FC_SEW_Read[5].StatusWord	 	:= FC_SEW_ModbusRead[5,0];
FC_SEW_Read[5].OutputCurrent	:= FC_SEW_ModbusRead[5,1];
FC_SEW_Read[5].DriveRPM			:= FC_SEW_ModbusRead[5,2];
FC_SEW_Read[6].StatusWord	 	:= FC_SEW_ModbusRead[6,0];
FC_SEW_Read[6].OutputCurrent	:= FC_SEW_ModbusRead[6,1];
FC_SEW_Read[6].DriveRPM			:= FC_SEW_ModbusRead[6,2];
FC_SEW_Read[7].StatusWord	 	:= FC_SEW_ModbusRead[7,0];
FC_SEW_Read[7].OutputCurrent	:= FC_SEW_ModbusRead[7,1];
FC_SEW_Read[7].DriveRPM			:= FC_SEW_ModbusRead[7,2];

(* Allocate FC_SEW_Read Status Word & limit RPM *)
FOR i:=0 TO 7 BY 1 DO
	FC_SEW_Read[i].OutputStageEnabled		:=	FC_SEW_ModbusRead[i,0].0;
	FC_SEW_Read[i].InverterReady			:=	FC_SEW_ModbusRead[i,0].1;
	FC_SEW_Read[i].PODataEnabled			:=	FC_SEW_ModbusRead[i,0].2;
	FC_SEW_Read[i].RampGeneratorSet			:=	FC_SEW_ModbusRead[i,0].3;
	FC_SEW_Read[i].CurrentParameterSet		:=	FC_SEW_ModbusRead[i,0].4;
	FC_SEW_Read[i].Fault_Warning			:=	FC_SEW_ModbusRead[i,0].5;
	FC_SEW_Read[i].LimitSwitchRightActive	:=	FC_SEW_ModbusRead[i,0].5;
	FC_SEW_Read[i].LimitSwitchLeftActive	:=	FC_SEW_ModbusRead[i,0].6;
	FC_SEW_Read[i].ErrorCode				:=	WORD_TO_BYTE(SHR(FC_SEW_ModbusRead[i,0],8));
	FC_SEW_Read[i].OutputCurrent			:=	FC_SEW_ModbusRead[i,1];

	IF FC_SEW_ModbusRead[i,2] > 65500 OR	 (* filter distortion of wrong drive feedback *)
	   FC_SEW_ModbusRead[i,2] < 35 THEN
		FC_SEW_ModbusRead[i,2] := 0;
	END_IF

	FC_SEW_Read[i].DriveRPM				:=	(FC_SEW_ModbusRead[i,2]);
END_FOR


(* allocate master read data*)
// SEW
FOR i:=0 TO enum_VFD_Function.Drive10 BY 1 DO
	IF FC_SchneiderRead[i].StatusWord > 0 THEN	// Bugfix for systems with SEW Drive and Schneider Milk Pump FC
		FC_MasterRead[i].Ready			:= FC_SchneiderRead[i].StatusBit_Ready;
		FC_MasterRead[i].FaultWarning	:= FC_SchneiderRead[i].StatusBit_Fault;
		FC_MasterRead[i].Overheated		:= NOT FC_SchneiderRead[i].DigitalIn.5 AND FC_SchneiderRead[i].StatusWord > 0;
		FC_MasterRead[i].SafeStop		:= NOT (FC_SchneiderRead[i].DigitalIn.2 OR FC_SchneiderRead[i].DigitalIn.3) AND FC_SchneiderRead[i].StatusWord > 0;
		FC_MasterRead[i].Manual			:= FC_SchneiderRead[i].DigitalIn.4;
		FC_MasterRead[i].ErrorCode		:= FC_SchneiderRead[i].LastFault;
		FC_MasterRead[i].DriveCurrent	:= WORD_TO_REAL(FC_SchneiderRead[i].MotorCurrent)/10;
		FC_MasterRead[i].DriveRPM		:= FC_SchneiderRead[i].CurrentRPM;
		FC_MasterRead[i].AnalogInValue	:= FC_SchneiderRead[i].In4_20mA;		
	ELSIF FC_SEW_Read[i].StatusWord > 0 THEN
		FC_MasterRead[i].Ready			:= FC_SEW_Read[i].InverterReady;
		FC_MasterRead[i].FaultWarning	:= FC_SEW_Read[i].Fault_Warning;
		FC_MasterRead[i].Overheated		:= FALSE;
		FC_MasterRead[i].SafeStop		:= FALSE;
		FC_MasterRead[i].Manual			:= FALSE;
		FC_MasterRead[i].ErrorCode		:= FC_SEW_Read[i].ErrorCode;
		FC_MasterRead[i].DriveCurrent	:= WORD_TO_REAL(FC_SEW_Read[i].OutputCurrent)/10;
		FC_MasterRead[i].DriveRPM		:= FC_SEW_Read[i].DriveRPM/5;
		FC_MasterRead[i].AnalogInValue	:= 0;		
	ELSE
		FC_MasterRead[i].Ready			:= FALSE;
		FC_MasterRead[i].FaultWarning	:= FALSE;
		FC_MasterRead[i].Overheated		:= FALSE;
		FC_MasterRead[i].SafeStop		:= FALSE;
		FC_MasterRead[i].Manual			:= FALSE;
		FC_MasterRead[i].ErrorCode		:= 0;
		FC_MasterRead[i].DriveCurrent	:= 0;
		FC_MasterRead[i].DriveRPM		:= 0;
		FC_MasterRead[i].AnalogInValue	:= 0;		
	END_IF	
END_FOR


// Schneider
FOR i:=enum_VFD_Function.MWR TO enum_VFD_Function.DL2 BY 1 DO
	IF FC_SchneiderRead[i].StatusWord > 0 THEN	// Bugfix for systems with SEW Drive and Schneider Milk Pump FC
		FC_MasterRead[i].Ready			:= FC_SchneiderRead[i].StatusBit_Ready;
		FC_MasterRead[i].FaultWarning	:= FC_SchneiderRead[i].StatusBit_Fault;
		FC_MasterRead[i].Overheated		:= NOT FC_SchneiderRead[i].DigitalIn.5 AND FC_SchneiderRead[i].StatusWord > 0;
		FC_MasterRead[i].SafeStop		:= NOT (FC_SchneiderRead[i].DigitalIn.2 OR FC_SchneiderRead[i].DigitalIn.3) AND FC_SchneiderRead[i].StatusWord > 0;
		FC_MasterRead[i].Manual			:= FC_SchneiderRead[i].DigitalIn.4;
		FC_MasterRead[i].ErrorCode		:= FC_SchneiderRead[i].LastFault;
		FC_MasterRead[i].DriveCurrent	:= WORD_TO_REAL(FC_SchneiderRead[i].MotorCurrent)/10;
		FC_MasterRead[i].DriveRPM		:= FC_SchneiderRead[i].CurrentRPM;
		FC_MasterRead[i].AnalogInValue	:= FC_SchneiderRead[i].In4_20mA;		
	ELSE
		FC_MasterRead[i].Ready			:= FALSE;
		FC_MasterRead[i].FaultWarning	:= FALSE;
		FC_MasterRead[i].Overheated		:= FALSE;
		FC_MasterRead[i].SafeStop		:= FALSE;
		FC_MasterRead[i].Manual			:= FALSE;
		FC_MasterRead[i].ErrorCode		:= 0;
		FC_MasterRead[i].DriveCurrent	:= 0;
		FC_MasterRead[i].DriveRPM		:= 0;
		FC_MasterRead[i].AnalogInValue	:= 0;		
	END_IF
END_FOR

