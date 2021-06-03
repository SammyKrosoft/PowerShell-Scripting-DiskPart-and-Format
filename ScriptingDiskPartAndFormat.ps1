<#
.SYNOPSIS
	This is a sample script to format and mount drives in preparation for use in
	a database availability group.  This script supports the AutoReseed feature
	of Exchange Server, as well as older configurations with a single
	database per volume.  It also supports isolated log volume configurations.


.DESCRIPTION
	Imports the CSV file and reads the diskmap to create an array for the actual
	formatting and mounting.
	
	
	The header line of the CSV file contains the following:
	
	"ServerName","StartDrive","DbPerVolume","DbLogIsolation",
		"VolumesRootFolder","DatabasesRootFolder","DbMap"

.NOTES
	New Terminology with Exchange Server 2013 and Exchange Server 2016:
	
	Autoreseed =
		A feature to quickly restoring database redundancy after a disk failure.
		If a disk fails, the database copies stored on that disk are
		automatically reseeded to a preconfigured (Mounted under
		C:\ExchangeVolumes) spare disk on the Mailbox server.

	Multiple Source Reseed =
		A target SATA disk can sustain about 100MB/s throughput. If you only
		have a single database on a disk then you are limited to thesource
		disk's throughput during reseed.  If you reseed from the active copy,
		you will at most get 20MB/s, wasting 80% of the target disk's
		capability.  With four copies of a database on disk and a reseed occurs,
		you will be reseeding from multiple source disks (three most likely)
		which means that your target disk's throughput utilization will go up
		20MB/s per copy using about 80% of the throughput capability.

	Disk Block =
		A set of DAG databases always grouped togther on a volume.  For example,
		if a DAG has three copies of each database and DB1, DB3, DB7, and DB9
		are in disk block one, then ServerA has a volume containing DB1, DB3,
		DB7, and DB9; ServerD has a volume containing DB1, DB3, DB7, and DB9;
		and ServerF has a volume containing DB1, DB3, DB7, and DB9.
	
	AutoDagDatabasesRootFolderPath =
		Specifies the directory containing the database mount points
		when using the AutoReseed feature of the DAG.
		AutoReseed uses a default path of C:\ExchangeDatabases.

	AutoDagVolumesRootFolderPath =
		Specifies the volume containing the mount points for all disks,
		INCLUDING spare disks, when using the AutoReseed feature of the DAG.
		AutoReseed uses a default path of C:\ExchangeVolumes.
	
	AutoDagDatabaseCopiesPerVolume =
		The AutoDagDatabaseCopiesPerVolume parameter is used to specify the
		configured number of database copies per volume. This parameter is used
		only with the AutoReseed feature of the DAG.
		Titans 26 and 33. Steelers Rule. Farcus

	Server.csv header information;

	Servername = "Server1"
		The host name of the computer.
			
	StartDrive = "2"
		The drive number you view in either (diskmgmt.msc) or using (from
		the cmdline or shell, diskpart LIST DISK) of the first disk to use
		for the DAG dbs and logs on the current server you are building. The
		first drive to format.
		
	Important Note:
	   	The Disk number starting point must be accurate on your machine and
		match your diskmap. Examples of Disk Numbers are shown below:
		
		Disk ###  Status         Size     Free     Dyn  Gpt
		--------  -------------  -------  -------  ---  ---
		Disk 0    Online          126 GB      0 B
		Disk 1    Offline         126 GB      0 B        *
		Disk 2    Online          126 GB      0 B        *
		Disk 3    Online          127 GB  1024 KB
		Disk 4    Offline         127 GB  1024 KB
		Disk 5    Online          127 GB   126 GB
		Disk 6    Online          127 GB   126 GB        *

		The script determines the number of disks required based on the number
		of databases assigned to the server, number of databases per volume,
		and collocated or isolated log volume.

	Important Note:
		This script assumes all disks for the DAG are consecutive.  For example,
		if StartDrive=2 and the script determines three disks are required,
		then disks two, three, and four will be reformatted and configured for
		Exchange.  Any previous data on those disks will be lost.

	VolumeFormat = "ReFS"
		Determines the formatting of the volumes hosting Exchange data.
		The value is either ReFS or NTFS.	

	DbPerVolume = "4"
		Determines the number of databases stored on a single volume.
	
	DbLogIsolation = "0"
		Determines if the script configures for database log isolation.  If set
		to "1" the script creates a structure where each database has a
		dedicated volume and each log has a separate dedicated volume.  Log
		isloation is not compatible with AutoReseed.  DbPerVolume must be set to
		DbPerVolume = "1".  If not then DbLogIsolation is disabled.
		
	VolumesRootFolder = "C:\ExchangeVolumes"
		When using the autoreseed feature, the default name and location is
		C:\ExchangeVolumes. If you customize this name in the Exchange Role
		Calculator, after creating the DAG you must change the
		AutoDagVolumesRootFolderPath attribute of each DAG using the
		Set-Databaseavailability cmdlet. The default is C:\ExchangeVolumes.

	DatabasesRootFolder = "C:\ExchangeDatabases"
		When using the autoreseed feature, the default name and location is
		C:\ExchangeDatabases. If you customize this name in the Exchange Role
		Calculator, after creating the DAG you must change the
		AutoDagDatabasesRootFolderPath attribute of each DAG using the
		Set-Databaseavailability cmdlet.  The default is C:\ExchangeDatabases.

	DbMap = "DB001,DB003,DB005,DB007"
		The names of the databases to be mounted on the server.  The Exchange
		Role Calculator exports the databases names in a specific order based on
		on the database distribution.  If using the AutoReseed feature, the
		order the databases are listed in DbMap is critical and must not be
		modified.

.PARAMETER ServerFile
	Specifies the name of the CSV file.  The parameter is optional and  defaults
	to "servers.csv" in the current directory if no parameter is provided.
	The path of the ServerFile should be enclosed in quotes if it contains
	embedded spaces.

.PARAMETER PrepareAutoReseedVolume
	Causes the script to format and mount an extra volume to be used for AutoReseed.
	The extra volume must be present at the time the scrpt is run.

.PARAMETER WhatIf
	Executes script but script displays what actions would be taken but does not
	actually take any actions.

.EXAMPLE
	./Diskpart.ps1 -ServerFile "D:\servers.csv"
	Runs the diskpart command and imports the diskmap information from the file
	servers.csv in the root directory of the D: drive.  No volume is mounted for
	AutoReseed.

.EXAMPLE
	./Diskpart.ps1 -ServerFile "D:\servers.csv" -PrepareAutoReseedVolume
	Runs the diskpart command and imports the diskmap information from the file
	servers.csv in the root directory of the D: drive.  The last physical disk will
	be formatted and mounted ready for AutoReseed.
	
.EXAMPLE
	./Diskpart.ps1 -ServerFile "D:\servers.csv" -WhatIf
	Runs the diskpart and displays what actions would be taken if WhatIf was not specified.
	The script imports the diskmap information from the file
	servers.csv in the root directory of the D: drive.  No volume is processed for
	AutoReseed.
#>

[CmdletBinding(SupportsShouldProcess=$True)]
Param (
	[Parameter(Position = 0)][String]$ServerFile = "Servers.csv",
	[Parameter(Mandatory=$False)][Switch]$PrepareAutoReseedVolume
)

<#==========================================================================
	Diskpart.ps1
	MICROSOFT 2016

	THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY
	KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
	IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
	PARTICULAR PURPOSE.

==========================================================================
#>

$ForegroundNormal = "Green"
$ForeGroundError = "Red"
$Version = "2.8"
$DataVersion = "2.2"

$DBLogIsolation = $True

Function Run-Diskpart
{
Param ([Array]$Commands)
$Tempfile = [System.IO.Path]::GetTempFileName()
Foreach ($Com in $Commands)
{
	$CMDLine = $CMDLine + $Com + ", "
	Add-Content $Tempfile $Com
}
	If ([bool]$WhatIfPreference) {
		Write-Host "What if: Performing the operation `"Diskpart /s $CMDLine`""
	}
If (![bool]$WhatIfPreference) {
	Write-Host "Diskpart /s $CMDLine" -ForegroundColor $ForeGroundNormal
	$Output = DiskPart /s $Tempfile
	$Output
	}
	Remove-Item $Tempfile -WhatIf:$False
}

Function PrepareVolumes()
{
	$Last = $LastDrive
	If ($PrepareAutoReseedVolume.IsPresent) {$Last += $AutoReseedVolumes}
	For ($Disk = $DiskStart; $Disk -le $Last; $Disk++) {
		Run-Diskpart "select disk $Disk","clean"
		Run-Diskpart "select disk $Disk","online disk"
		Run-Diskpart "select disk $Disk","attributes disk clear readonly","convert MBR"
		Run-Diskpart "select disk $Disk","offline disk"
		$VolPath = "$ExchangeVols\ExVol" + $Disk
		If ((Test-Path $VolPath) -eq $False) {
			New-Item $VolPath -type Directory
		}
		If ($VolumeFormat -ne "ReFS") {
			$Format = "Format FS=NTFS UNIT=64k Label=ExVol" + $Disk + " QUICK"
			$Mount = 'assign mount="' + $Volpath + '"'	
			Run-Diskpart "select disk $Disk","attributes disk clear readonly","online disk","convert GPT noerr","create partition primary","$Format","$Mount"
		}
		Else {
			Run-Diskpart "select disk $Disk","attributes disk clear readonly","online disk","convert GPT noerr","create partition primary"
			Start-Sleep 10
Get-Partition -disknumber $disk -partitionnumber 2|Format-Volume –AllocationUnitSize 65536 –FileSystem REFS –NewFileSystemLabel “ExVol$Disk" –SetIntegrityStreams:$false -confirm:$false
			Add-PartitionAccessPath -DiskNumber $disk -PartitionNumber 2 -AccessPath "$Volpath"-Passthru |Set-Partition -NoDefaultDriveLetter:$True
			#note on line above, code was added to address the bug with add-partitionaccesspath above by setting the partition back to no default drive letter.
		}
	}
}

Function PrepareDatabases()
{
	$Vol = $DiskStart
	$x = 0
	Foreach ($DB in $DbMap) {
		$DBPath = "$ExchangeDBs\$DB"
		If ((Test-Path $DBPath) -eq $False) {
			New-Item $DBPath -type Directory
		}
		If ($x -eq 0) {
			$Volume = "$ExchangeVols\ExVol" + $Vol
			$x = $DBperVolume
			$Vol++
		}
		$Mount = 'assign mount="' + $DBPath + '"'
		Run-Diskpart "select volume $Volume", "$Mount"
		$x--
		$DBPath = "$ExchangeDBs\$DB"
		New-Item $DBPath\$DB.db -type Directory
		New-Item $DBPath\$DB.log -type Directory
		If ($DBLogIsolation -and ($DBperVolume -eq "1")) {
			$DBPath = "$DBPath\$DB" + ".log"
			$Volume = "$ExchangeVols\ExVol" + $Vol
			$Mount = 'assign mount="' + $DBPath + '"'
			Run-Diskpart "select volume $Volume", "$Mount"
			$Vol++
		}
	}
	If ($Script:DBLogIsolation -eq $True) {
		For ($Vol = $DiskStart; $Vol -le $LastDrive; $Vol++) {
			Write-Host "Log Isolation is enabled so AutoReseed mount points will be removed" -ForegroundColor $ForeGroundNormal
			$Volume = "$ExchangeVols\ExVol" + $Vol
			$Mount = 'remove mount="' + $Volume + '"'
			Run-Diskpart "select volume $Volume", "$Mount"
			}
		If (![bool]$WhatIfPreference) {
			Remove-Item $ExchangeVols -Recurse
			}
		Else {
			Write-Host "What if: Performing the operation `"Remove-Item $ExchangeVols -Recurse`""
			}
		}
	Else {
		Write-Host "Rearranging drive mounts to assign Performance counters to database mounts" -ForegroundColor $ForeGroundNormal
		For ($Vol = $DiskStart; $Vol -le $LastDrive; $Vol++) {
			$Volume = "$ExchangeVols\ExVol" + $vol
			$Mount = 'assign mount="' + $Volume + '"'
			$RemoveMount = 'remove mount="' + $Volume + '"'
			Run-Diskpart "select volume $Volume", "$RemoveMount","$Mount"
		}
	}
}

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
$IsAdmin = $true
If ($IsAdmin) {
	Start-Transcript -WhatIf:$false
	Run-Diskpart "list disk"
	Write-Host "Diskpart script version: $Version" -ForegroundColor $ForeGroundNormal
	Write-Host "Diskpart data version: $DataVersion" -ForegroundColor $ForeGroundNormal
	Write-Host "Attempting to read CSV file: $ServerFile" -ForegroundColor $ForegroundNormal
	If (Test-Path "$ServerFile") {
		[Array]$DiskPart = Import-CSV $ServerFile
		If ($DataVersion -eq $DiskPart[0].StartDrive) {
			$Found = $False
		    	$Machine = get-wmiobject "Win32_ComputerSystem"
		    	$MachineName = $Machine.Name
			Foreach ($Server in $Diskpart) {
				If ($MachineName -eq $Server.ServerName) {
					$Found = $True
					[Array]$Diskmap = $Server.DbMap
					If ($Server.DbLogIsolation -eq "1") {
						$DBLogIsolation = $True
					}
					Else {
						$DBLogIsolation = $False
					}
			$VolumeFormat = $Server.VolumeFormat					
			$ExchangeVols = $Server.VolumesRootFolder
					$ExchangeDBs = $Server.DatabasesRootFolder
					$DBperVolume = [int]$Server.DBperVolume
					[Array]$DbMap = $Server.DbMap -split ","
					$DiskStart = [int]$Server.StartDrive
					$AutoReseedVolumes = $Server.AutoReseedVolumes
					If ($DBperVolume -gt 1) {
						$LastDrive = $DiskStart - 1 + $DbMap.Count/$DBperVolume
					}
					Else {
						If ($DBLogIsolation) {
							$LastDrive = $DiskStart - 1 + $DbMap.Count * 2
						}
						Else {
							$LastDrive = $DiskStart - 1 + $DbMap.Count
						}
					}
					Write-Host "Found entry for $MachineName in $ServerFile file" -ForegroundColor $ForeGroundNormal
					Write-Host "First Drive Number: $DiskStart" -ForegroundColor $ForeGroundNormal
					Write-Host "Last Drive Number: $LastDrive" -ForegroundColor $ForeGroundNormal
					Write-Host "Autoreseed volumes: $AutoReseedVolumes" -ForegroundColor $ForeGroundNormal
					PrepareVolumes
					PrepareDatabases
				}
			}
			If ($Found -eq $False) {
				Write-Host "Could not find entry for $MachineName in $ServerFile file" -ForegroundColor $ForeGroundError
				Stop-Transcript
				Exit 1
			}
		}
		Else {
			Write-Host "Mismatch between script data version ($DataVersion) and $ServerFile data version (" $DiskPart[0].StartDrive ")" -ForegroundColor $ForeGroundError
			Stop-Transcript
			Exit 2
		}
	}
	Else {
		Write-Host "Cannot find CSV file: $ServerFile.  Exiting on keystroke..." -ForegroundColor $ForeGroundError
		$Host.UI.RawUI.ReadKey() | out-null
		Stop-Transcript
		Exit 3
	}
	Stop-Transcript
}
ELse {
	Write-Host "You must run this script from an elevated command prompt.  Exiting on keystroke..." -ForegroundColor $ForeGroundError
	$Host.UI.RawUI.ReadKey() | out-null
	Stop-Transcript
	Exit 4
}
