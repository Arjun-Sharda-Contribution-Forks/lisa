﻿$result = ""
$CurrentTestResult = CreateTestResultObject
$resultArr = @()

$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if ($isDeployed)
{
	try
	{
        #region Prepare / Upload all the required files to guest VM.
		RemoteCopy -uploadTo $AllVMData.PublicIP -port $AllVMData.SSHPort -files $currentTestData.files -username $user -password $password -upload
        if ($currentTestData.TestParameters)
        {
            $ConstantsFile = "$LogDir\constants.sh"
            Set-Content -Value "#Generated by LISAv2" -Path $ConstantsFile -Force
            foreach ($parameter in $currentTestData.TestParameters.param)
            {
                Add-Content -Value $parameter -Path $ConstantsFile -Force
                LogMsg "$parameter added to constants.sh file"
            }
            LogMsg "constants.sh file ready."
            RemoteCopy -uploadTo $AllVMData.PublicIP -port $AllVMData.SSHPort -files $ConstantsFile -username $user -password $password -upload
        }
        $out = RunLinuxCmd -username $user -password $password -ip $AllVMData.PublicIP -port $AllVMData.SSHPort -command "chmod +x *" -runAsSudo

        #Execute the script.
		LogMsg "Executing : $($currentTestData.testScript)"
		RunLinuxCmd -username $user -password $password -ip $AllVMData.PublicIP -port $AllVMData.SSHPort -command "bash -c ./$($currentTestData.testScript)" -runAsSudo -runMaxAllowedTime 7200 -maxRetryCount 0
		RemoteCopy -download -downloadFrom $AllVMData.PublicIP -files "/home/$user/TestState.log, /home/$user/TestExecution.log, /home/$user/TestExecutionError.log" -downloadTo $LogDir -port $AllVMData.SSHPort -username $user -password $password
        $testResult = Get-Content $LogDir\TestState.log

        LogMsg (Get-Content -Path "$LogDir\TestExecution.log")
        LogMsg ("---------Please review below STDERR logs------------------")
        LogMsg (Get-Content -Path "$LogDir\TestExecutionError.log")
		LogMsg ("----------------------------------------------------------")
        LogMsg "Test result : $testResult"
        
		if ($testResult -eq "PASS")
		{
			LogMsg "Test PASS"
		}
		else
		{
			LogMsg "Test Failed"
		}
	}

	catch
	{
		$ErrorMessage =  $_.Exception.Message
		LogMsg "EXCEPTION : $ErrorMessage"   
	}
	Finally
	{
		if (!$testResult)
		{
			$testResult = "Aborted"
		}
		$resultArr += $testResult
	}   
}

else
{
	$testResult = "Aborted"
	$resultArr += $testResult
}

$CurrentTestResult.TestResult = GetFinalResultHeader -resultarr $resultArr

#Clean up the setup
DoTestCleanUp -CurrentTestResult $CurrentTestResult -testName $currentTestData.testName -ResourceGroups $isDeployed

#Return the result and summery to the test suite script..
return $CurrentTestResult