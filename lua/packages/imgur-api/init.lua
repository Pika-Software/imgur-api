-- HTTP Content
import( Either( file.Exists( "packages/http-content/package.lua", "LUA" ), "packages/http-content", "https://raw.githubusercontent.com/Pika-Software/http-content/master/package.json" ) )

-- Libraries
local promise = promise
local string = string
local http = http
local util = util

-- Variables
local imgurID = CreateConVar( "imgur_clientid", "", bit.bor( FCVAR_ARCHIVE, FCVAR_PROTECTED ), " - https://api.imgur.com/oauth2/addclient" )
local assert = assert
local type = type

module( "imgur" )

ImageInfo = promise.Async( function( imageID )
    local clientID = imgurID:GetString()
    assert( clientID ~= "", "no clientID" )

    imageID = string.match( imageID, "^https?://imgur%.com[/\\](%w+)[%./\\]?" ) or imageID

    local ok, result = http.Fetch( "https://api.imgur.com/3/image/" .. imageID, {
        ["Authorization"] = "Client-ID " .. clientID
    } ):SafeAwait()

    if not ok then return promise.Reject( result ) end
    if result.code ~= 200 then return promise.Reject( "invalid response http code - " .. result.code ) end

    local tbl = util.JSONToTable( result.body )
    if not tbl then return promise.Reject( "incorrect response" ) end
    if not tbl.success then return promise.Reject( "failed" ) end

    local data = tbl.data
    if not data then return promise.Reject( "no data" ) end

    return data
end )

Upload = promise.Async( function( binaryData, contentType, title, description, name, disableAudio, album )
    local clientID = imgurID:GetString()
    assert( clientID ~= "", "no clientID" )

    if string.IsURL( binaryData ) then contentType = "URL" end

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
        ["Authorization"] = "Client-ID " .. clientID
    } ):SafeAwait()

    if not ok then return promise.Reject( result ) end
    if result.code ~= 200 then return promise.Reject( "invalid response http code - " .. result.code ) end

    local tbl = util.JSONToTable( result.body )
    if not tbl then return promise.Reject( "incorrect response" ) end
    if not tbl.success then return promise.Reject( "failed" ) end

    local data = tbl.data
    if not data then return promise.Reject( "no data" ) end

    return data
end )

Download = promise.Async( function( imageID, allowNSFW )
    local ok, result = ImageInfo( imageID ):SafeAwait()
    if not ok then return promise.Reject( result ) end

    if result.nsfw and not allowNSFW then return promise.Reject( "nsfw content" ) end

    local ok, result = http.DownloadImage( result.link ):SafeAwait()
    if not ok then return promise.Reject( result ) end

    return result
end )

Material = promise.Async( function( imageID, parameters, allowNSFW )
    local ok, result = ImageInfo( imageID ):SafeAwait()
    if not ok then return promise.Reject( result ) end

    if result.nsfw and not allowNSFW then return promise.Reject( "nsfw content" ) end

    local ok, result = http.DownloadMaterial( result.link, parameters ):SafeAwait()
    if not ok then return promise.Reject( result ) end

    return result
end )
