
_ = require( 'underscore')
{ EventEmitter } = require 'events'
hashcash = require 'hashcashgen'


Gossipmonger = require '../lib/gossipmonger'

rand = (min,max) -> Math.floor(Math.random() * (max - min + 1)) + min
PORT = parseInt( process.argv[2] ) || rand( 9002, 10000);
isHost = PORT <= 9002


DEFAULT_POW = 3

defaultArguments = (PORT)->
    DEAD_PEER_PHI: 1
    id: 'defaultID' + PORT
    transport:
        host: 'localhost'
        port: PORT

class Lodestone extends EventEmitter
    constructor: ({ @options, @data, @seeds } = {}) ->
        @seeds ?= []
        @gossip = new Gossipmonger( @options or defaultArguments(PORT), { seeds: @seeds } )
        @_proxyEvents()
        @activeSearches = []
        @peers = {}

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

    _handleGossipUpdate: (peerId, key, value) =>
        console.log "Noticed an update by peer: #{ peerId }, key: #{ key }, value: ", value
        @_handleSearch( key, value) if @_isSearch( key )
        @_handleGraphInfo( peerId, key, value ) if @_isGraphInfo( key )

    _handleSearch: (search, hashes) ->
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
    
    _handleGraphInfo: (peerId, key, peerGraph) ->
        console.log "Lodestone: GraphInfo from #{ peerId }, is: ", peerGraph
        peers = _.keys( @peers )
        @peers[peerId] = peerGraph
        @emit 'update-peers'

    _updateLocalGraph: ->
        for peer in @gossip.storage.livePeers()
            @peers[peer.id] ?= []
        console.log "Lodestone: Updating local graph", @peers
        @gossip.update( 'graph', @peers )

    _trimGraph: (peers, graph ) ->
        trim = (value, stop) ->
            for sub_key, sub_val in value
                if _.indexOf( peers, sub_key ) is not -1
                    delete value[sub_key]
                else
                    peers.push sub_key
                    value[ sub_key ] = trim( sub_key, sub_val )
            value
        trim( graph )
            


    _handleGossipNewPeer: (peer) =>
        console.log "Lodestone: New peer", peer
        @_updateLocalGraph()
        @emit 'update-peers'

    _handleGossipPeerLive: (peer) =>
        console.log "Lodestone: Peer live", peer
        @_updateLocalGraph()
        @emit 'update-peers'

    _handleGossipPeerDead: (peer) =>
        console.log "Lodestone: Peer dead.", peer
        @_updateLocalGraph()
        @emit 'update-peers'

    _isSearch: (str) ->
        str.indexOf( '|' ) >= 0

    _isGraphInfo: (str) ->
        str is 'graph'

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

    localSeed =
        "id": "example"
        "transport":
            "host": "localhost"
            "port": 9001

    lode = new Lodestone
        data: {}
    lode.start()

    for count in [0..3]
        other = new Lodestone
            options: defaultArguments(9002 + count)
            seeds: [ localSeed ]
        other.start()

    console.log( 'Lodestone created.' )


