# Set default check interval to 10 seconds
param(
    [Parameter(Mandatory)]
    [object]$Config,
    [int]$CheckInterval = 10,
    [int]$Timeout = 3600
)

# After displaying status (including first load), show confirmation with countdown
for ($countdown = $CheckInterval; $countdown -gt 0; $countdown--) {
    $prompt = "Press 'x' to quit, 'b' to go back to menu, or wait $countdown seconds to continue: "
    $userInput = [UserInteraction]::PromptWithTimeout($prompt, 1)
    switch ($userInput) {
        'x' { break 2 }
        'b' { return }
        default { }
    }
} 