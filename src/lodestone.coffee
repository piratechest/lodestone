
Gossipmonger = require 'gossipmonger'
{ EventEmitter } = require 'events'
hashcash = require 'hashcashgen'

rand = (min,max) -> Math.floor(Math.random() * (max - min + 1)) + min
PORT = parseInt( process.argv[2] ) || rand( 9002, 10000);
isHost = process.argv[2]?


DEFAULT_POW = 5

defaultArguments =
	id: 'defaultID'
	transport:
		host: 'localhost'
		port: PORT

defaultOptions =
	seeds: if isHost then [] else [ id: 'seed1', transport: { host: 'localhost', port: 9001 } ] 


class Lodestone extends EventEmitter
	constructor: ->
		@gossip = new Gossipmonger( defaultArguments, defaultOptions )
		@_proxyEvents()
		@gossip.transport.listen ->
			console.log "Lodestone gossip transport listening on port #{ PORT }"
		@gossip.gossip()

	listen: (callback) ->
		@gossip.transport.listen( callback )

	addSearch: (str) ->
		mask = @_maskSearch( str )
		pow = @_getPOW( mask, DEFAULT_POW )
		@gossip.update( mask, pow )

	_proxyEvents: ->
		@gossip.on 'error', @_handleGossipError
		@gossip.on 'update', @_handleGossipUpdate
		@gossip.on 'new peer', @_handleGossipNewPeer
		@gossip.on 'peer live', @_handleGossipPeerLive
		@gossip.on 'peer dead', @_handleGossipPeerDead

	_handleGossipError: =>
		console.log arguments

	_handleGossipUpdate: (peer, key, hashes) =>
		# TODO: MEssage format is it: mask, pow, hashes
		if @_checkPOW( key, hashes )
			@gossip.update( key, hashes.slice( 0, -1 ) )

	_handleGossipNewPeer: =>
		console.log arguments

	_handleGossipPeerLive: =>
		console.log arguments

	_handleGossipPeerDead: =>
		console.log arguments

	_isSearch: (key, value) ->

	_maskSearch: (str) ->
		tags = str.split( /\W+/ )
		masked = for tag in tags
			i = rand( 0, tag.length - 1 )
			"#{ tag[i] }#{ i }"
		masked.join(':')


	_getPOW: (input, difficulty) ->
		hashcash( input, x ).replace( "#{input}:", '' ) for x in [1..difficulty]

	_checkPOW: (input, hashcashes) ->
		for x in [(hashcashes.length - 1)..1]
			return false unless hashcash.check( input, x, "#{ input }:#{ hashcashes[ x ] }" )
		return true





module.exports = Lodestone

lode = new Lodestone()
lode.on 'error', -> console.log 'error'
lode.on 'update', -> console.log 'update'
lode.on 'new peer', -> console.log 'new peer'
