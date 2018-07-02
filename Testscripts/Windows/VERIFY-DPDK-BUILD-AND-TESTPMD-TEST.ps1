$result = ""
$CurrentTestResult = CreateTestResultObject
$resultArr = @()

$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if ($isDeployed)
{
	
	try
	{
		$noClient = $true
		$noServer = $true
		foreach ( $vmData in $allVMData )
		{
			if ( $vmData.RoleName -imatch "client" )
			{
				$clientVMData = $vmData
				$noClient = $false
			}
			elseif ( $vmData.RoleName -imatch "server" )
			{
				$noServer = $fase
				$serverVMData = $vmData
			}
		}
		if ( $noClient )
		{
			Throw "No any master VM defined. Be sure that, Client VM role name matches with the pattern `"*master*`". Aborting Test."
		}
		if ( $noServer )
		{
			Throw "No any slave VM defined. Be sure that, Server machine role names matches with pattern `"*slave*`" Aborting Test."
		}
		#region CONFIGURE VM FOR TERASORT TEST
		LogMsg "CLIENT VM details :"
		LogMsg "  RoleName : $($clientVMData.RoleName)"
		LogMsg "  Public IP : $($clientVMData.PublicIP)"
		LogMsg "  SSH Port : $($clientVMData.SSHPort)"
		LogMsg "  Internal IP : $($clientVMData.InternalIP)"
		LogMsg "SERVER VM details :"
		LogMsg "  RoleName : $($serverVMData.RoleName)"
		LogMsg "  Public IP : $($serverVMData.PublicIP)"
		LogMsg "  SSH Port : $($serverVMData.SSHPort)"
		LogMsg "  Internal IP : $($serverVMData.InternalIP)"
		
		#
		# PROVISION VMS FOR LISA WILL ENABLE ROOT USER AND WILL MAKE ENABLE PASSWORDLESS AUTHENTICATION ACROSS ALL VMS IN SAME HOSTED SERVICE.	
		#
		ProvisionVMsForLisa -allVMData $allVMData -installPackagesOnRoleNames "none"

		#endregion

		if($EnableAcceleratedNetworking -or ($currentTestData.AdditionalHWConfig.Networking -imatch "SRIOV"))
		{
			$DataPath = "SRIOV"
            LogMsg "Getting SRIOV NIC Name."
            $clientNicName = (RunLinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -command "route | grep '^default' | grep -o '[^ ]*$' 2>&1 | ip route | grep default | tr ' ' '\n' | grep eth").Trim()
            LogMsg "CLIENT SRIOV NIC: $clientNicName"
            $serverNicName = (RunLinuxCmd -ip $clientVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -command "route | grep '^default' | grep -o '[^ ]*$' 2>&1 | ip route | grep default | tr ' ' '\n' | grep eth").Trim()
            LogMsg "SERVER SRIOV NIC: $serverNicName"
            if ( $serverNicName -eq $clientNicName)
            {
                $nicName = $clientNicName
            }
            else
            {
                Throw "Server and client SRIOV NICs are not same."
            }
		}
		else
		{
			$DataPath = "Synthetic"
            LogMsg "Getting Active NIC Name."
            $clientNicName = (RunLinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -command "route | grep '^default' | grep -o '[^ ]*$' 2>&1 | ip route | grep default | tr ' ' '\n' | grep eth").Trim()
            LogMsg "CLIENT NIC: $clientNicName"
            $serverNicName = (RunLinuxCmd -ip $clientVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -command "route | grep '^default' | grep -o '[^ ]*$' 2>&1 | ip route | grep default | tr ' ' '\n' | grep eth").Trim()
            LogMsg "SERVER NIC: $serverNicName"
            if ( $serverNicName -eq $clientNicName)
            {
                $nicName = $clientNicName
            }
            else
            {
                Throw "Server and client NICs are not same."
            }
		}

		LogMsg "Generating constansts.sh ..."
		$constantsFile = "$LogDir\constants.sh"
		Set-Content -Value "#Generated by Azure Automation." -Path $constantsFile
		Add-Content -Value "vms=$($serverVMData.RoleName),$($clientVMData.RoleName)" -Path $constantsFile
		Add-Content -Value "server=$($serverVMData.InternalIP)" -Path $constantsFile	
		Add-Content -Value "client=$($clientVMData.InternalIP)" -Path $constantsFile
		Add-Content -Value "nicName=eth1" -Path $constantsFile
		Add-Content -Value "pciAddress=0002:00:02.0" -Path $constantsFile

		foreach ( $param in $currentTestData.TestParameters.param)
		{
			Add-Content -Value "$param" -Path $constantsFile
			if ( $param -imatch "modes" )
			{
				$modes = ($param.Replace("modes=",""))
			} 
		}
		LogMsg "constanst.sh created successfully..."
		LogMsg "test modes : $modes"
		LogMsg (Get-Content -Path $constantsFile)
		#endregion

		#region EXECUTE TEST
		$myString = @"
cd /root/
./dpdkTestPmd.sh 2>&1 > dpdkConsoleLogs.txt
. azuremodules.sh
collect_VM_properties
"@
		Set-Content "$LogDir\StartDpdkTestPmd.sh" $myString
		RemoteCopy -uploadTo $clientVMData.PublicIP -port $clientVMData.SSHPort -files ".\$constantsFile,.\Testscripts\Linux\azuremodules.sh,.\Testscripts\Linux\dpdkSetup.sh,.\Testscripts\Linux\dpdkTestPmd.sh,.\$LogDir\StartDpdkTestPmd.sh" -username "root" -password $password -upload
		RemoteCopy -uploadTo $clientVMData.PublicIP -port $clientVMData.SSHPort -files $currentTestData.files -username "root" -password $password -upload

		$out = RunLinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -command "chmod +x *.sh"
		$testJob = RunLinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -command "./StartDpdkTestPmd.sh" -RunInBackground
		#endregion

		#region MONITOR TEST
		while ( (Get-Job -Id $testJob).State -eq "Running" )
		{
			$currentStatus = RunLinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -command "tail -2 dpdkConsoleLogs.txt | head -1"
			LogMsg "Current Test Staus : $currentStatus"
			WaitFor -seconds 20
		}
		$finalStatus = RunLinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -command "cat /root/state.txt"
		RemoteCopy -downloadFrom $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -download -downloadTo $LogDir -files "*.csv, *.txt, *.log, *.tar.gz"
		$uploadResults = $true
		if ( $finalStatus -imatch "TestFailed")
		{
			LogErr "Test failed. Last known status : $currentStatus."
			$testResult = "FAIL"
		}
		elseif ( $finalStatus -imatch "TestAborted")
		{
			LogErr "Test Aborted. Last known status : $currentStatus."
			$testResult = "ABORTED"
		}
		elseif ( ($finalStatus -imatch "TestCompleted") -and $uploadResults )
		{
			LogMsg "Test Completed."
			$testResult = "PASS"
		}
		elseif ( $finalStatus -imatch "TestRunning")
		{
			LogMsg "Powershell backgroud job for test is completed but VM is reporting that test is still running. Please check $LogDir\zkConsoleLogs.txt"
			LogMsg "Contests of summary.log : $testSummary"
			$testResult = "PASS"
		}
		
		try
		{
			$testpmdDataCsv = Import-Csv -Path $LogDir\dpdkTestPmd.csv
			LogMsg "Uploading the test results.."
			$dataSource = $xmlConfig.config.$TestPlatform.database.server
			$DBuser = $xmlConfig.config.$TestPlatform.database.user
			$DBpassword = $xmlConfig.config.$TestPlatform.database.password
			$database = $xmlConfig.config.$TestPlatform.database.dbname
			$dataTableName = $xmlConfig.config.$TestPlatform.database.dbtable
			$TestCaseName = $xmlConfig.config.$TestPlatform.database.testTag
			
			if ($dataSource -And $DBuser -And $DBpassword -And $database -And $dataTableName) 
			{
				$GuestDistro	= cat "$LogDir\VM_properties.csv" | Select-String "OS type"| %{$_ -replace ",OS type,",""}
				if ( $UseAzureResourceManager )
				{
					$HostType	= "Azure-ARM"
				}
				else
				{
					$HostType	= "Azure"
				}
				
				$HostBy	= ($xmlConfig.config.$TestPlatform.General.Location).Replace('"','')
				$HostOS	= cat "$LogDir\VM_properties.csv" | Select-String "Host Version"| %{$_ -replace ",Host Version,",""}
				$GuestOSType	= "Linux"
				$GuestDistro	= cat "$LogDir\VM_properties.csv" | Select-String "OS type"| %{$_ -replace ",OS type,",""}
				$GuestSize = $clientVMData.InstanceSize
				$KernelVersion	= cat "$LogDir\VM_properties.csv" | Select-String "Kernel version"| %{$_ -replace ",Kernel version,",""}
				$IPVersion = "IPv4"
				$ProtocolType = "TCP"
				$connectionString = "Server=$dataSource;uid=$DBuser; pwd=$DBpassword;Database=$database;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"

				$SQLQuery = "INSERT INTO $dataTableName (TestPlatFrom,TestCaseName,TestDate,HostType,HostBy,HostOS,GuestOSType,GuestDistro,GuestSize,KernelVersion,LISVersion,IPVersion,ProtocolType,DataPath,DPDKVersion,TestMode,Max_Rxpps,Txpps,Rxpps,Txbytes,Rxbytes,Txpackets,Rxpackets,Re_Txpps,Re_Txbytes,Re_Txpackets,Tx_PacketSize_KBytes,Rx_PacketSize_KBytes) VALUES "
				foreach( $mode in $testpmdDataCsv) 
				{
					$SQLQuery += "('Azure','$TestCaseName','$(Get-Date -Format yyyy-MM-dd)','$HostType','$HostBy','$HostOS','$GuestOSType','$GuestDistro','$GuestSize','$KernelVersion','Inbuilt','$IPVersion','$ProtocolType','$DataPath','$($mode.DpdkVersion)','$($mode.TestMode)','$($mode.MaxRxPps)','$($mode.TxPps)','$($mode.RxPps)','$($mode.TxBytes)','$($mode.RxBytes)','$($mode.TxPackets)','$($mode.RxPackets)','$($mode.ReTxPps)','$($mode.ReTxBytes)','$($mode.ReTxPackets)','$($mode.TxPacketSize)','$($mode.RxPacketSize)'),"
					LogMsg "Collected performace data for $($mode.TestMode) mode."
				}
				$SQLQuery = $SQLQuery.TrimEnd(',')
				LogMsg $SQLQuery
				$connection = New-Object System.Data.SqlClient.SqlConnection
				$connection.ConnectionString = $connectionString
				$connection.Open()

				$command = $connection.CreateCommand()
				$command.CommandText = $SQLQuery
				
				$result = $command.executenonquery()
				$connection.Close()
				LogMsg "Uploading the test results done!!"
			}
			else{
				LogMsg "Invalid database details. Failed to upload result to database!"
			}
		}
		catch{
			$ErrorMessage =  $_.Exception.Message
			LogMsg "EXCEPTION : $ErrorMessage"
		}
		LogMsg "Test result : $testResult"
		LogMsg ($testpmdDataCsv | Format-Table | Out-String)
	}
	catch
	{
		$ErrorMessage =  $_.Exception.Message
		LogMsg "EXCEPTION : $ErrorMessage"   
	}
	Finally
	{
		$metaData = "DPDK RESULT"
		if (!$testResult)
		{
			$testResult = "Aborted"
		}
		$resultArr += $testResult
		$CurrentTestResult.TestSummary += CreateResultSummary -testResult $testResult -metaData "DPDK-TESTPMD" -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
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
