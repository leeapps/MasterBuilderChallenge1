write-host "Please choose a directory to store the script log"
function ChooseFolder([string]$Message, [string]$InitialDirectory)
{
    $app = New-Object -ComObject Shell.Application
    $folder = $app.BrowseForFolder(0, $Message, 0, $InitialDirectory)
    $selectedDirectory = $folder.Self.Path 
    return $selectedDirectory
}
$logfolder = ChooseFolder -Message "Please select a log file directory" -InitialDirectory 'MyComputer' 
$logfile = $logfolder + '\' + (Get-Date -Format o |ForEach-Object {$_ -Replace ':', '.'}) + "Guardians.txt"
write-host "Script result log can be found at $logfile" -ForegroundColor Green

if ( !(Get-Module -Name Rubrik -ErrorAction SilentlyContinue) ) 
    {
        write-host ("Rubrik Module not installed. Please verify installation and retry.") -BackgroundColor Red
        write-host "Terminating Script" -BackgroundColor Red
        add-content $logfile ("Rubrik Module not found. Please verify installation and retry.")
        add-content $logfile "You can install the module by running : Install-Module -Name Rubrik"
        return
    }
write-host "Getting Credentials from user prompt" -ForegroundColor Green
add-content $logfile "Getting Credentials from user prompt"
$Credentials = Get-Credential
$RubrikClusterIP = read-host "Please enter a Rubrik Cluster IP or FQDN"
try
{
    Connect-Rubrik -Server $RubrikClusterIP -Credential $Credentials -ErrorAction Stop |out-null
    add-content $logfile ('Connected to Rubrik Cluster at ' + $RubrikClusterIP)
    add-content $logfile '----------------------------------------------------------------------------------------------------'
}
catch
{
    write-host "Failed to connect to Rubrik Cluster" -BackgroundColor Red
    write-host $RubrikClusterIP
    write-host $Error[0]
    write-host "Terminating Script" -BackgroundColor Red
    add-content $logfile "Failed to connect to Rubrik Cluster"
    add-content $logfile $RubrikClusterIP
    add-content $logfile $Error[0]
    add-content $logfile "Terminating Script"
    return
}
$ReportArray=@()
write-host "Getting a list of VM's from the Rubrik Cluster" -ForegroundColor Green
add-content $logfile "Getting a list of VM's from the Rubrik Cluster"
$RubrikVMs = Get-Rubrikvm | Select Name, effectiveSlaDomainName,hostName,clusterName,id
write-host "Getting a list of Missed Snapshots for all VM's" -ForegroundColor Green
add-content $logfile "Getting a list of Missed Snapshots for all VM's"
write-host "If you have a large number of VM's this will take some time to process" -ForegroundColor Green
foreach ($vm in $RubrikVMs) {
	$VMName = $vm.Name
	$SLADomain = $vm.effectiveSlaDomainName
	$ClusterName = $vm.clusterName
	$CurrentHost = $vm.hostName
	$URL = "vmware/vm/" + $vm.id + "/missed_snapshot"
	$MissedSnapshots = Invoke-RubrikRESTCall -Endpoint $URL -Method GET
	$MissedSnapshotsTotal = $MissedSnapshots.total
	$ReportLine = new-object PSObject
	$ReportLine | Add-Member -MemberType NoteProperty -Name "VMName" -Value "$VMName"
	$ReportLine | Add-Member -MemberType NoteProperty -Name "SLADomain" -Value "$SLADomain"
	$ReportLine | Add-Member -MemberType NoteProperty -Name "ClusterName" -Value "$ClusterName"
	$ReportLine | Add-Member -MemberType NoteProperty -Name "CurrentVMHost" -Value "$CurrentHost"
	$ReportLine | Add-Member -MemberType NoteProperty -Name "MissedSnapshots" -Value "$MissedSnapshotsTotal"
	$ReportArray += $ReportLine
}
$PromptTitle = "How do you want to see the report?"
$PromptMessage = "Do you want to see all entries or sort and filter by the number of missed snapshots?" 
$Filter = New-Object System.Management.Automation.Host.ChoiceDescription "&Filter", "Filters the results"
$All = New-Object System.Management.Automation.Host.ChoiceDescription "&all", "Shows all the Results"
$PromptOptions = [System.Management.Automation.Host.ChoiceDescription[]]($Filter, $All)
$PromptResult = $host.ui.PromptForChoice($PromptTitle, $PromptMessage, $PromptOptions, 0) 

switch ($PromptResult)
    {
        0 {"Filtering the results"}
        1 {"Showing All Results"}
    }
if ($PromptResult -eq 0)
{
	$FormatedReport = $ReportArray | Where-Object {$_.MissedSnapshots -ne 0} | Sort-Object -Descending MissedSnapshots
	$FormatedReport | Format-Table
}
If ($PromptResult -eq 1)
{
	$ReportArray | Format-Table
}
