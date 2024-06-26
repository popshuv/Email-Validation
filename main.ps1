Add-Type -AssemblyName 'System.Net.Http'

# DEFINE VARIABLES
$config = @{
    API_KEY = "<INSERT YOUR API KEY>"  
    URI_SEND_FILE = "https://bulkapi.zerobounce.net/v2/sendfile"  
    URI_FILE_STATUS = "https://bulkapi.zerobounce.net/v2/filestatus"  
    URI_GET_FILE = "https://bulkapi.zerobounce.net/v2/getfile"  
    IN_FILE = "<INPUT FILE>"  
    OUT_FILE = "<OUTPUT FILE>"  
    FILE_CHECK_WAIT = 20   
    RUN_DATE = Get-Date
}

try {
    # Prepare the file content for the HTTP request
    $client = New-Object System.Net.Http.HttpClient
    $content = New-Object System.Net.Http.MultipartFormDataContent
    $fileStream = [System.IO.File]::OpenRead($config.IN_FILE)
    $fileName = [System.IO.Path]::GetFileName($config.IN_FILE)
    
    # Create the file content
    $fileContent = New-Object System.Net.Http.StreamContent($fileStream)
    $fileContent.Headers.ContentDisposition = New-Object System.Net.Http.Headers.ContentDispositionHeaderValue('form-data')
    $fileContent.Headers.ContentDisposition.Name = 'file'
    $fileContent.Headers.ContentDisposition.FileName = $fileName
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('text/csv')
    
    # Add the file content and API key to the multipart content
    $content.Add($fileContent)
    $content.Add($(New-Object System.Net.Http.StringContent($config.API_KEY)), 'api_key')
    $content.Add($(New-Object System.Net.Http.StringContent('1')), 'email_address_column')

    # Send the HTTP request
    $response = $client.PostAsync($config.URI_SEND_FILE, $content)
    $result = $response.Result

    # Check if the request was successful
    if ($result.IsSuccessStatusCode) {
        $resultContent = $result.Content.ReadAsStringAsync().Result | ConvertFrom-Json

        if ($resultContent.success) {
            $fileStatusID = $resultContent.file_id
            Write-Host "File status ID: $fileStatusID"
            $resultContent = $result.Content.ReadAsStringAsync().Result | ConvertFrom-Json

            $validationResponse = $client.GetStringAsync("$($config.URI_GET_FILE)?api_key=$($config.API_KEY)&file_id=$fileStatusID").Result
            $validationResponse | Out-File -FilePath $config.OUT_FILE
            
        } else {
            Write-Host "Failed to send file: $($resultContent.error)"
        }
    } else {
        Write-Host "HTTP request failed with status code: $($result.StatusCode)"
    }

} catch {
    Write-Host "An error occurred: $($_.Exception.Message)"
    exit 1

} finally {
    # Clean up resources
    if ($fileStream) {
        $fileStream.Dispose()
    }
    if ($fileContent) {
        $fileContent.Dispose()
    }
}

# Wait for file to be validated
$complete = $false

while(!$complete) {
    Write-Host "Status Check $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
    $request = Invoke-RestMethod -Method Get -Uri ($config.URI_FILE_STATUS + "?api_key=$($config.API_KEY)&file_id=$($resultContent.file_id)")
    $complete = $request.file_status -eq "Complete"
    Write-Host "Status: $($request.complete_percentage) Complete. $($request.file_status) - $($request.file_name) `n"
    Start-Sleep -Seconds $config.FILE_CHECK_WAIT
}

