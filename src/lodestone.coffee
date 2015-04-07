
Gossipmonger = require 'gossipmonger'
_ = require( 'underscore')
{ EventEmitter } = require 'events'
hashcash = require 'hashcashgen'

rand = (min,max) -> Math.floor(Math.random() * (max - min + 1)) + min
PORT = parseInt( process.argv[2] ) || rand( 9002, 10000);
isHost = PORT <= 9002


DEFAULT_POW = 3

defaultArguments =
    id: 'defaultID' + PORT
    transport:
        host: 'localhost'
        port: PORT

class Lodestone extends EventEmitter
    constructor: ({ @data, @seeds } = {}) ->
        @seeds ?= []
        @gossip = new Gossipmonger( defaultArguments, { seeds: @seeds } )
        @_proxyEvents()
        @activeSearches = []

    start: ->
        console.log "Lodestone starting..."
        @started = true
        @gossip.transport.listen =>
            console.log "Lodestone gossip transport listening on port #{ PORT } trying #{ @seeds.length } seeds"
        @gossip.gossip()

    ping: ->
        @gossip.update( 'time', Date.now() )

    updateData: (data) ->
        console.log "Updating local data: ", data
        @data = data

    addSearch: (str) ->
        console.log( "Lodestone constructing search for [#{ str }]")
        mask = @_maskSearch( str )
        pow = @_getPOW( mask, DEFAULT_POW )
        combined = @_combineMaskPOW( mask, pow )
        console.log( "Masked search with appended hashcash: #{ combined }")
        @activeSearches = @_stringTotags( str )
        @gossip.update( combined, [] )


    _proxyEvents: ->
        @gossip.on 'error', @_handleGossipError
        @gossip.on 'update', @_handleGossipUpdate
        @gossip.on 'new peer', @_handleGossipNewPeer
        @gossip.on 'peer live', @_handleGossipPeerLive
        @gossip.on 'peer dead', @_handleGossipPeerDead

    _handleGossipError: =>
        # console.log "Lodestone ERROR: ", arguments

    _handleGossipUpdate: (peer, search, hashes) =>
        console.log "Noticed an update by peer: #{ peer }, key: #{ search }, value: ", hashes
        return unless @_isSearch(search)
        console.log( 'Is search: true')
        [mask, pow] = @_separateMaskPOW(search)
        if @_checkPOW( mask, pow )
            console.log "Hashcash: ok."
            results = @_checkLocalData( mask )
            @_updateIfOutstanding( mask, hashes )
            search = @_combineMaskPOW( mask, @_decrementPOW( pow ) )
            update = _.uniq( hashes or [] ).concat( results or [] )
            console.log( 'Updating local data: ', update )
            @gossip.update( search, update )
        else
            console.log "Hashcash: fail."

    _handleGossipNewPeer: =>
        @emit 'update-peers'
        console.log "Lodestone: New peer", arguments

    _handleGossipPeerLive: =>
        @emit 'update-peers'
        console.log "Lodestone: Peer live", arguments

    _handleGossipPeerDead: =>
        @emit 'update-peers'
        console.log "Lodestone: Peer dead.", arguments

    _isSearch: (str) ->
        str.indexOf( '|' ) >= 0

    _updateIfOutstanding: (masks, newHashes) ->
        for tag in @activeSearches
            for mask in @_expandMask( masks )
                match = @_tagMatchesMask( tag, mask )
                @emit 'data', { mask: masks, hashes: newHashes }

    _checkLocalData: (mask) =>
        return unless @data
        console.log "Checking local data: ", @data
        m = @_expandMask( mask )
        console.log "Expanded mask: ", m
        results = []
        for own infoHash, tags of @data
            console.log "Checking #{ infoHash }", tags
            for item in m 
                for tag in tags
                    results.push( infoHash ) if @_tagMatchesMask( tag, item )
        console.log( "Found local items for masked search (#{ mask }): ", results )
        _.uniq( results )

    _tagMatchesMask: (tag, mask) ->
        match = tag[ mask[1] ] is mask[ 0 ]
        console.log( tag, " matches: ", match)
        match
    
    _expandMask: (mask) ->
        [ m[0], parseInt( m[1..-1] ) ] for m in mask.split( ':')

    _stringTotags: (str) -> str.split( /\W+/ )

    _maskSearch: (str) ->
        tags = @_stringTotags( str )
        masked = for tag in tags
            i = rand( 0, tag.length - 1 )
            "#{ tag[i] }#{ i }"
        masked.join(':')

    _combineMaskPOW: (mask, hashcashes) ->
        "#{ mask }|#{ hashcashes.join(',') }"

    _separateMaskPOW: (key) ->
        [ mask, hashcashes ] = key.split( '|' )
        [ mask, hashcashes.split( ',' ) ]

    _getPOW: (input, difficulty) ->
        hashcash( input, x ).replace( "#{input}:", '' ) for x in [1..difficulty]

    _decrementPOW: (pow) ->
        pow.slice( 0, -1 )

    _checkPOW: (input, hashcashes) ->
        for x in [(hashcashes.length - 1)..1]
            return false unless hashcash.check( input, x, "#{ input }:#{ hashcashes[ x ] }" )
        return true

module.exports = Lodestone

if isHost
    lode = new Lodestone
        data: {}
    lode.start()
    console.log( 'Lodestone created.' )


