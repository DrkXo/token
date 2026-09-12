---@param _ TokenPalette
---@return table<string, vim.api.keyset.highlight>
local function sidekick(_)
  return {
    SidekickDiffContext = { link = 'DiffChange' },
    SidekickDiffAdd = { link = 'DiffText' },
    SidekickDiffDelete = { link = 'DiffDelete' },
    SidekickSign = { link = 'Special' },
    SidekickChat = { link = 'NormalFloat' },
    SidekickCliMissing = { link = 'DiagnosticError' },
    SidekickCliAttached = { link = 'Special' },
    SidekickCliStarted = { link = 'DiagnosticWarn' },
    SidekickCliInstalled = { link = 'DiagnosticOk' },
    SidekickCliUnavailable = { link = 'DiagnosticError' },
    SidekickLocDelim = { link = 'Delimiter' },
    SidekickLocFile = { link = '@markup.link' },
    SidekickLocNum = { link = '@attribute' },
    SidekickLocRow = { link = 'SidekickLocDelim' },
    SidekickLocCol = { link = 'SidekickLocDelim' },
  }
end

return sidekick
