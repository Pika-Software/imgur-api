install( "packages/http-content", "https://github.com/Pika-Software/http-content" )

-- Libraries
local promise = promise
local string = string
local cvars = cvars
local http = http
local util = util

-- Variables
local select = select
local assert = assert
local type = type

CreateConVar( "imgur_clientid", "", bit.bor( FCVAR_ARCHIVE, FCVAR_PROTECTED ), "https://api.imgur.com/oauth2/addclient" )

module( "imgur" )

do

    local function clientIDChanged( str )
        if #string.Trim( str ) == 0 then
            HasClientID = false
            ClientID = nil
            return
        end

        HasClientID = true
        ClientID = str
    end

    clientIDChanged( cvars.String( "imgur_clientid", "" ) )
    cvars.AddChangeCallback( "imgur_clientid", function( _, __, value ) clientIDChanged( value ) end )

end

function GetImageID( str )
    return string.match( str, "^https?://.*imgur%.com[/\\](%w+)[%./\\]?" ) or str
end

ImageInfo = promise.Async( function( imageID )
    assert( HasClientID, "no clientID" )

    local ok, result = http.Fetch( "https://api.imgur.com/3/image/" .. GetImageID( imageID ), {
        ["Authorization"] = "Client-ID " .. ClientID
    } ):SafeAwait()

    if not ok then return promise.Reject( result ) end

    local code = result.code
    if code ~= 200 then
        return promise.Reject( select( -1, http.GetStatusDescription( code ) ) )
    end

    local tbl = util.JSONToTable( result.body )
    if not tbl then return promise.Reject( "incorrect response" ) end
    if not tbl.success then return promise.Reject( "failed" ) end

    local data = tbl.data
    if not data then return promise.Reject( "no data" ) end

    return data
end )

Upload = promise.Async( function( binaryData, contentType, title, description, name, disableAudio, album )
    assert( HasClientID, "no clientID" )

    if string.IsURL( binaryData ) then
        contentType = "URL"
    end

    local parameters = {
        ["description"] = type( description ) == "string" and description or nil,
        ["album"] = type( album ) == "string" and album or nil,
        ["title"] = type( title ) == "string" and title or nil,
        ["name"] = type( name ) == "string" and name or nil,
        ["type"] = "base64"
    }

    if not contentType or contentType == "" or contentType == "image" then
        parameters.image = util.Base64Encode( binaryData )
    elseif contentType == "video" then
        parameters.disableAudio = disable_audio == true and "1" or "0"
        parameters.video = util.Base64Encode( binaryData )
    elseif contentType == "url" then
        parameters.image = binaryData
        parameters.type = "URL"
    else
        return promise.Reject( "unknown content type" )
    end

    local ok, result = http.Post( "https://api.imgur.com/3/upload", parameters, {
        ["Authorization"] = "Client-ID " .. ClientID
    } ):SafeAwait()

    if not ok then return promise.Reject( result ) end

    local code = result.code
    if code ~= 200 then
        return promise.Reject( select( -1, http.GetStatusDescription( code ) ) )
    end

    local tbl = util.JSONToTable( result.body )
    if not tbl then return promise.Reject( "incorrect response" ) end
    if not tbl.success then return promise.Reject( "failed" ) end

    local data = tbl.data
    if not data then return promise.Reject( "no data" ) end

    return data
end )

Download = promise.Async( function( imageID, allowNSFW )
    if not HasClientID then
        local extension = string.GetExtensionFromFilename( imageID )
        if not extension then extension = "png" end

        imageID = GetImageID( imageID ) .. "." .. extension

        local ok, result = http.DownloadImage( "https://i.imgur.com/" .. imageID ):SafeAwait()
        if ok then return result end

        ok, result = http.DownloadImage( "https://proxy.duckduckgo.com/iu/?u=https://i.imgur.com/" .. imageID ):SafeAwait()
        if ok then return result end

        return promise.Reject( result )
    end

    local ok, result = ImageInfo( imageID ):SafeAwait()
    if not ok then
        return promise.Reject( result )
    end

    if result.nsfw and not allowNSFW then
        return promise.Reject( "nsfw content" )
    end

    local ok, result = http.DownloadImage( result.link ):SafeAwait()
    if ok then return result end

    return promise.Reject( result )
end )

Material = promise.Async( function( imageID, parameters, allowNSFW )
    if not HasClientID then
        local extension = string.GetExtensionFromFilename( imageID )
        if not extension then extension = "png" end

        imageID = GetImageID( imageID ) .. "." .. extension

        local ok, result = http.DownloadMaterial( "https://i.imgur.com/" .. imageID, parameters ):SafeAwait()
        if ok then return result end

        ok, result = http.DownloadMaterial( "https://proxy.duckduckgo.com/iu/?u=https://i.imgur.com/" .. imageID, parameters ):SafeAwait()
        if ok then return result end

        return promise.Reject( result )
    end

    local ok, result = ImageInfo( imageID ):SafeAwait()
    if not ok then return promise.Reject( result ) end

    if result.nsfw and not allowNSFW then return promise.Reject( "nsfw content" ) end

    local ok, result = http.DownloadMaterial( result.link, parameters ):SafeAwait()
    if not ok then return promise.Reject( result ) end

    return result
end )
