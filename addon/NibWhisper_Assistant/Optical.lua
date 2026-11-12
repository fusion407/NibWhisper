-- Original, optional visual transport. Only data is displayed; no HTTP or input automation.
local Nib = _G.NibWhisper
if not Nib then return end
local Optical = {}
Nib.Optical = Optical
local columns, rows, cell, pageSize = 64, 24, 2, 512
local marker = {5,2,7,1,6,3,0,4,3,6,1,7,2,5,4,0}
local magic = "NIBPIX2!"
local textures, frame, packet, pages, page, elapsed, nonce, whole
local bitValue = {[0]=1,2,4,8,16,32,64,128}

local function adler(str)
    local a,b = 1,0
    for i=1,#str do a=(a+str:byte(i))%65521; b=(b+a)%65521 end
    return b*65536.0+a
end
local function u16(n) return string.char(math.floor(n/256)%256,n%256) end
local function u32(n) return string.char(math.floor(n/16777216)%256,math.floor(n/65536)%256,math.floor(n/256)%256,n%256) end
local function color(texture,n)
    local gray = (24 + n * 24) / 255
    texture:SetColorTexture(gray, gray, gray, 1)
end
local function updateScale()
    if not frame then return end
    local width = GetPhysicalScreenSize and GetPhysicalScreenSize()
    local scale = width and width > 0 and UIParent:GetWidth() / width or 1 / (UIParent:GetEffectiveScale() or 1)
    if scale > 0 then frame:SetScale(scale) end
end
local function createFrame()
    if frame then return end
    frame=CreateFrame("Frame","NibWhisperOptical",UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(1000)
    frame:SetSize(columns*cell,(rows+1)*cell)
    frame:SetPoint("BOTTOMRIGHT",UIParent,"BOTTOMRIGHT",0,0)
    frame:EnableMouse(false)
    updateScale()
    local bg=frame:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0,0,0,1)
    for i=0,columns-1 do
        local t=frame:CreateTexture(nil,"OVERLAY");t:SetSize(cell,cell);t:SetPoint("TOPLEFT",i*cell,0);color(t,marker[i%#marker+1])
    end
    for i=0,columns*rows-1 do
        local t=frame:CreateTexture(nil,"ARTWORK");t:SetSize(cell,cell);t:SetPoint("TOPLEFT",(i%columns)*cell,-(math.floor(i/columns)+1)*cell);textures[i+1]=t
    end
    frame:SetScript("OnUpdate",function(_,dt)
        elapsed=elapsed+dt
        if elapsed>=0.18 then elapsed=0;page=(page+1)%pages;Optical:RenderPage() end
    end)
    frame:Hide()
end
function Optical:RenderPage()
    if not packet or not frame then return end
    local part=packet:sub(page*pageSize+1,(page+1)*pageSize)
    local bytes=magic..u32(nonce)..u16(page)..u16(pages)..u16(#part)..u32(#packet)..u32(whole)..u32(adler(part)).."\0\0"..part
    local byteIndex,bitIndex=1,7
    for i=1,columns*rows do
        local value=0
        for _=1,3 do
            local byte=bytes:byte(byteIndex) or 0
            value=value*2+math.floor(byte/bitValue[bitIndex])%2
            bitIndex=bitIndex-1
            if bitIndex<0 then byteIndex=byteIndex+1;bitIndex=7 end
        end
        color(textures[i],value)
    end
end
function Optical:SetPacket(value,requestId)
    if type(value)~="string" or #value==0 or #value>180000 then return false end
    textures=textures or {}
    createFrame()
    packet,pages,page,elapsed,nonce,whole=value,math.ceil(#value/pageSize),0,0,adler(requestId or ""),adler(value)
    updateScale();self:RenderPage();frame:Show()
    return true
end
function Optical:ClearPacket()
    packet=nil
    if frame then frame:Hide() end
end
-- Pure protocol hooks used by offline interoperability tests.
Optical.Adler32=adler
Optical.Header=function(value,requestId,index)
    local part=value:sub(index*pageSize+1,(index+1)*pageSize)
    return magic..u32(adler(requestId))..u16(index)..u16(math.ceil(#value/pageSize))..u16(#part)..u32(#value)..u32(adler(value))..u32(adler(part)).."\0\0"..part
end
