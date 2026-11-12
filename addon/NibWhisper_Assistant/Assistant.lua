-- Switches on Nib's assistant. The core addon builds chat, the mascot and the helper bridge only when this has loaded.
local A = _G.NibWhisper
if not A then return end
A.Assistant = {version = "0.7.11"}
