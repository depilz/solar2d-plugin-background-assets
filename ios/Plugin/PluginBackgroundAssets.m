// plugin.backgroundAssets for iOS devices: the native backend under the Lua front (docs/backend.rst). The front's
// source is embedded at build time (kFront, generated from lua/plugin_backgroundAssets.lua), and loading the library
// runs it with the backend table.

#import "PluginBackgroundAssets.h"

#import <Foundation/Foundation.h>
#import <BackgroundAssets/BackgroundAssets.h>

#include <errno.h>
#include <stdio.h>
#include <unistd.h>

#include "PluginBackgroundAssetsFront.h"

static const char kFrontChunkName[] = "=plugin_backgroundAssets.lua";
static const char kPluginDomain[] = "plugin.backgroundAssets";
static const int kUnsupportedCode = 1;
static const int kInvalidArgumentCode = 2;

// The transient 513 (D12, docs/backend.rst): the policy's numbers, in one place.
static const int64_t kRemoveWaitMilliseconds = 250; // the longest a path lookup waits for a plugin remove in flight
static const int kRetriesOn513 = 4; // the lookups after the first one that fails with NSCocoaErrorDomain 513
static const useconds_t kRetrySleepMilliseconds = 5; // the sleep before each of them
static const NSTimeInterval kRetryBudgetMilliseconds = 50; // the time from the first lookup within which they run

// pathForFile's links, under system.CachesDirectory
static NSString *const kLinksFolder = @"plugin.backgroundAssets";

// The removed-pack record, in the app's user defaults
static NSString *const kRemovedAssetPacksKey = @"plugin.backgroundAssets.removedAssetPacks";

// Pushes the arguments of a later call onto L and returns how many it pushed.
typedef int (^PushArguments)( lua_State *L );

// A Lua function held in the registry, called later in the Corona main Lua state.
typedef struct
{
	lua_State *coronaL;
	int ref;
} LuaCallback;

static LuaCallback Reference( lua_State *L, int index )
{
	lua_pushvalue( L, index );
	return (LuaCallback){ CoronaLuaGetCoronaThread( L ), luaL_ref( L, LUA_REGISTRYINDEX ) };
}

// Calls the callback on a later turn of the main queue with the arguments push gives. A one-shot callback drops its
// reference at that call (D7).
static void Call( LuaCallback callback, BOOL isOneShot, PushArguments push )
{
	dispatch_async( dispatch_get_main_queue(), ^{
		lua_State *coronaL = callback.coronaL;
		int top = lua_gettop( coronaL );
		lua_rawgeti( coronaL, LUA_REGISTRYINDEX, callback.ref );
		if ( isOneShot ) { luaL_unref( coronaL, LUA_REGISTRYINDEX, callback.ref ); }
		CoronaLuaDoCall( coronaL, push ? push( coronaL ) : 0, 0 );
		lua_settop( coronaL, top );
	} );
}

// Calls the function at index once, on a later turn of the main queue, with the arguments push gives.
static void CallLater( lua_State *L, int index, PushArguments push )
{
	Call( Reference( L, index ), YES, push );
}

static void PushNSString( lua_State *L, NSString *value )
{
	if ( value ) { lua_pushstring( L, value.UTF8String ); } else { lua_pushnil( L ); }
}

// A raw error (docs/backend.rst): unsupported, in the plugin's domain.
static void PushUnsupported( lua_State *L, const char *callName )
{
	lua_createtable( L, 0, 3 );
	lua_pushstring( L, kPluginDomain );
	lua_setfield( L, -2, "domain" );
	lua_pushinteger( L, kUnsupportedCode );
	lua_setfield( L, -2, "code" );
	lua_pushfstring( L, "%s is not available in this build of the plugin", callName );
	lua_setfield( L, -2, "message" );
}

// The iOS version whose Background Assets calls the OS has, at the versions the front gates on, or nil below 26.0.
static NSString *ApiVersion( void )
{
	if ( @available( iOS 26.0, * ) ) {
		if ( ! [BAAssetPackManager class] ) { return nil; } // the weak-linked framework is not loaded
		if ( @available( iOS 27.0, * ) ) { return @"27.0"; }
		if ( @available( iOS 26.4, * ) ) { return @"26.4"; }
		return @"26.0";
	}
	return nil;
}

static NSString *OSVersion( void )
{
	NSOperatingSystemVersion version = [NSProcessInfo processInfo].operatingSystemVersion;
	if ( version.patchVersion ) {
		return [NSString stringWithFormat:@"%ld.%ld.%ld", (long)version.majorVersion, (long)version.minorVersion,
			(long)version.patchVersion];
	}
	return [NSString stringWithFormat:@"%ld.%ld", (long)version.majorVersion, (long)version.minorVersion];
}

// "apple" or "self" from the app's Info.plist BAUsesAppleHosting, nil when BAHasManagedAssetPacks is not set (D9).
static NSString *Hosting( void )
{
	NSBundle *bundle = [NSBundle mainBundle];
	if ( ! [[bundle objectForInfoDictionaryKey:@"BAHasManagedAssetPacks"] boolValue] ) { return nil; }
	return [[bundle objectForInfoDictionaryKey:@"BAUsesAppleHosting"] boolValue] ? @"apple" : @"self";
}

// backend.info()
static int Info( lua_State *L )
{
	lua_createtable( L, 0, 4 );
	lua_pushstring( L, "ios" );
	lua_setfield( L, -2, "platform" );
	PushNSString( L, OSVersion() );
	lua_setfield( L, -2, "osVersion" );
	PushNSString( L, ApiVersion() );
	lua_setfield( L, -2, "apiVersion" );
	PushNSString( L, Hosting() );
	lua_setfield( L, -2, "hosting" );
	return 1;
}

// backend.defer( fn )
static int Defer( lua_State *L )
{
	luaL_checktype( L, 1, LUA_TFUNCTION );
	CallLater( L, 1, nil );
	return 0;
}

// Raw data (docs/backend.rst). The pushers touch sAssetPacks, so they run on the main thread.

// The value of BASuccessesErrorKey and BAFailuresErrorKey. Those symbols exist only from iOS 27, and a reference to
// them would keep the library from linking into an app built against an older SDK.
static NSString *const kSuccessesErrorKey = @"BASuccesses";
static NSString *const kFailuresErrorKey = @"BAFailures";

// The packs last pushed to Lua, by id: the objects Apple's methods that take a BAAssetPack get.
static NSMutableDictionary *sAssetPacks;

static void PushAssetPack( lua_State *L, BAAssetPack *pack ) API_AVAILABLE( ios( 26.0 ) )
{
	if ( ! sAssetPacks ) { sAssetPacks = [[NSMutableDictionary alloc] init]; }
	sAssetPacks[pack.identifier] = pack;

	lua_createtable( L, 0, 5 );
	PushNSString( L, pack.identifier );
	lua_setfield( L, -2, "id" );
	lua_pushnumber( L, pack.downloadSize );
	lua_setfield( L, -2, "downloadSize" );
	lua_pushnumber( L, pack.version );
	lua_setfield( L, -2, "version" );
	if ( @available( iOS 27.0, * ) ) {
		PushNSString( L, pack.language );
		lua_setfield( L, -2, "language" );
	}
	if ( pack.userInfo ) {
		lua_pushlstring( L, pack.userInfo.bytes, pack.userInfo.length );
		lua_setfield( L, -2, "userInfo" );
	}
}

static void PushAssetPacks( lua_State *L, id<NSFastEnumeration> packs ) API_AVAILABLE( ios( 26.0 ) )
{
	lua_newtable( L );
	int i = 0;
	for ( BAAssetPack *pack in packs ) {
		PushAssetPack( L, pack );
		lua_rawseti( L, -2, ++i );
	}
}

static void PushStrings( lua_State *L, id<NSFastEnumeration> strings )
{
	lua_newtable( L );
	int i = 0;
	for ( NSString *string in strings ) {
		PushNSString( L, string );
		lua_rawseti( L, -2, ++i );
	}
}

static id ValueOfClass( NSDictionary *dictionary, NSString *key, Class valueClass )
{
	id value = dictionary[key];
	return [value isKindOfClass:valueClass] ? value : nil;
}

static void PushError( lua_State *L, NSError *error ) API_AVAILABLE( ios( 26.0 ) );

// The failures of a multi-pack error: an array of { assetPack, error }.
static void PushFailures( lua_State *L, NSDictionary *failures ) API_AVAILABLE( ios( 26.0 ) )
{
	lua_newtable( L );
	int i = 0;
	for ( BAAssetPack *pack in failures ) {
		lua_createtable( L, 0, 2 );
		PushAssetPack( L, pack );
		lua_setfield( L, -2, "assetPack" );
		PushError( L, failures[pack] );
		lua_setfield( L, -2, "error" );
		lua_rawseti( L, -2, ++i );
	}
}

// A raw error, with successes and failures when its userInfo has them.
static void PushError( lua_State *L, NSError *error )
{
	NSDictionary *userInfo = error.userInfo;
	lua_createtable( L, 0, 6 );
	PushNSString( L, error.domain );
	lua_setfield( L, -2, "domain" );
	lua_pushinteger( L, error.code );
	lua_setfield( L, -2, "code" );
	PushNSString( L, error.localizedDescription );
	lua_setfield( L, -2, "message" );
	PushNSString( L, ValueOfClass( userInfo, BAAssetPackIdentifierErrorKey, [NSString class] ) );
	lua_setfield( L, -2, "assetPackId" );

	NSSet *successes = ValueOfClass( userInfo, kSuccessesErrorKey, [NSSet class] );
	if ( successes ) {
		PushAssetPacks( L, successes );
		lua_setfield( L, -2, "successes" );
	}
	NSDictionary *failures = ValueOfClass( userInfo, kFailuresErrorKey, [NSDictionary class] );
	if ( failures ) {
		PushFailures( L, failures );
		lua_setfield( L, -2, "failures" );
	}
}

static void PushManifest( lua_State *L, BAAssetPackManifest *manifest ) API_AVAILABLE( ios( 27.0 ) )
{
	lua_createtable( L, 0, 5 );
	PushAssetPacks( L, manifest.assetPacks );
	lua_setfield( L, -2, "assetPacks" );
	PushNSString( L, manifest.primaryLanguage );
	lua_setfield( L, -2, "primaryLanguage" );
	PushStrings( L, manifest.availableLanguages );
	lua_setfield( L, -2, "availableLanguages" );
	PushNSString( L, manifest.resolvedLanguage );
	lua_setfield( L, -2, "resolvedLanguage" );
	PushAssetPacks( L, manifest.localizedAssetPacks );
	lua_setfield( L, -2, "localizedAssetPacks" );
}

// The result pushResult pushes, or nil and the raw error; returns how many values it pushed.
static int PushResult( lua_State *L, NSError *error, PushArguments pushResult ) API_AVAILABLE( ios( 26.0 ) )
{
	if ( ! error ) { return pushResult( L ); }
	lua_pushnil( L );
	PushError( L, error );
	return 2;
}

// done( result ) with the result pushResult pushes, or done( nil, error ).
static void Finish( LuaCallback done, NSError *error, PushArguments pushResult ) API_AVAILABLE( ios( 26.0 ) )
{
	Call( done, YES, ^( lua_State *L ) { return PushResult( L, error, pushResult ); } );
}

static NSError *PluginError( int code, NSString *message )
{
	return [NSError errorWithDomain:@(kPluginDomain) code:code userInfo:@{ NSLocalizedDescriptionKey: message }];
}

static void FinishWithTrue( LuaCallback done, NSError *error ) API_AVAILABLE( ios( 26.0 ) )
{
	Finish( done, error, ^( lua_State *L ) {
		lua_pushboolean( L, 1 );
		return 1;
	} );
}

static void FinishWithStatus( LuaCallback done, BAAssetPackStatus status, NSError *error ) API_AVAILABLE( ios( 26.0 ) )
{
	Finish( done, error, ^( lua_State *L ) {
		lua_pushnumber( L, status );
		return 1;
	} );
}

// Arguments. The front has checked them (docs/backend.rst); the checks here only keep a bad call from crashing.

static NSString *CheckNSString( lua_State *L, int index )
{
	return [NSString stringWithUTF8String:luaL_checkstring( L, index )];
}

static NSString *OptNSString( lua_State *L, int index )
{
	const char *value = luaL_optstring( L, index, NULL );
	return value ? [NSString stringWithUTF8String:value] : nil;
}

static NSArray *CheckNSStrings( lua_State *L, int index )
{
	luaL_checktype( L, index, LUA_TTABLE );
	NSMutableArray *strings = [NSMutableArray array];
	int count = (int)lua_objlen( L, index );
	for ( int i = 1; i <= count; i++ ) {
		lua_rawgeti( L, index, i );
		[strings addObject:CheckNSString( L, -1 )];
		lua_pop( L, 1 );
	}
	return strings;
}

// done, the last argument of every asynchronous call
static LuaCallback ReferenceDone( lua_State *L )
{
	luaL_checktype( L, -1, LUA_TFUNCTION );
	return Reference( L, lua_gettop( L ) );
}

// Resolving packs by id: from sAssetPacks, or else from Apple, through the manifest on iOS 27.

typedef void (^AssetPacksHandler)( NSSet *packs, NSError *error );

static NSError *AssetPackNotFound( NSString *assetPackId ) API_AVAILABLE( ios( 26.0 ) )
{
	NSDictionary *userInfo = @{
		NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No asset pack has the identifier %@.", assetPackId],
		BAAssetPackIdentifierErrorKey: assetPackId,
	};
	return [NSError errorWithDomain:BAManagedErrorDomain code:BAManagedErrorCodeAssetPackNotFound userInfo:userInfo];
}

// The packs lookup finds for ids, or the error for the first id it finds none for.
static void PickAssetPacks( NSArray *ids, BAAssetPack *(^lookup)( NSString *assetPackId ), AssetPacksHandler then )
	API_AVAILABLE( ios( 26.0 ) )
{
	NSMutableSet *packs = [NSMutableSet set];
	for ( NSString *assetPackId in ids ) {
		BAAssetPack *pack = lookup( assetPackId );
		if ( ! pack ) { then( nil, AssetPackNotFound( assetPackId ) ); return; }
		[packs addObject:pack];
	}
	then( packs, nil );
}

static void FetchAssetPacks( NSArray *ids, AssetPacksHandler then ) API_AVAILABLE( ios( 26.0 ) )
{
	BAAssetPackManager *manager = BAAssetPackManager.sharedManager;
	if ( @available( iOS 27.0, * ) ) {
		[manager getManifestWithCompletionHandler:^( BAAssetPackManifest *manifest, NSError *error ) {
			if ( error ) { then( nil, error ); return; }
			PickAssetPacks( ids, ^( NSString *assetPackId ) { return [manifest assetPackWithIdentifier:assetPackId]; },
				then );
		}];
		return;
	}
	[manager getAllAssetPacksWithCompletionHandler:^( NSSet *all, NSError *error ) {
		if ( error ) { then( nil, error ); return; }
		NSMutableDictionary *byId = [NSMutableDictionary dictionary];
		for ( BAAssetPack *pack in all ) {
			byId[pack.identifier] = pack;
		}
		PickAssetPacks( ids, ^( NSString *assetPackId ) { return (BAAssetPack *)byId[assetPackId]; }, then );
	}];
}

static void ResolveAssetPacks( NSArray *ids, AssetPacksHandler then ) API_AVAILABLE( ios( 26.0 ) )
{
	NSMutableSet *packs = [NSMutableSet set];
	NSMutableArray *missing = [NSMutableArray array];
	for ( NSString *assetPackId in ids ) {
		BAAssetPack *pack = sAssetPacks[assetPackId];
		if ( pack ) { [packs addObject:pack]; } else { [missing addObject:assetPackId]; }
	}
	if ( ! missing.count ) { then( packs, nil ); return; }
	FetchAssetPacks( missing, ^( NSSet *fetched, NSError *error ) {
		if ( error ) { then( nil, error ); return; }
		then( [packs setByAddingObjectsFromSet:fetched], nil );
	} );
}

// The download delegate

static LuaCallback sDownloadHandler = { NULL, LUA_NOREF };

// handler( { phase, assetPack, ... } ) on the main queue; fill adds the phase's own fields to the table on top.
static void SendDownload( const char *phase, BAAssetPack *pack, void (^fill)( lua_State *L ) ) API_AVAILABLE( ios( 26.0 ) )
{
	Call( sDownloadHandler, NO, ^( lua_State *L ) {
		lua_createtable( L, 0, 4 );
		lua_pushstring( L, phase );
		lua_setfield( L, -2, "phase" );
		PushAssetPack( L, pack );
		lua_setfield( L, -2, "assetPack" );
		if ( fill ) { fill( L ); }
		return 1;
	} );
}

API_AVAILABLE( ios( 26.0 ) )
@interface PluginBackgroundAssetsDownloadDelegate : NSObject <BAManagedAssetPackDownloadDelegate>
@end

@implementation PluginBackgroundAssetsDownloadDelegate

- (void)downloadOfAssetPackBegan:(BAAssetPack *)assetPack
{
	SendDownload( "began", assetPack, nil );
}

- (void)downloadOfAssetPackPaused:(BAAssetPack *)assetPack
{
	SendDownload( "paused", assetPack, nil );
}

- (void)downloadOfAssetPack:(BAAssetPack *)assetPack hasProgress:(NSProgress *)progress
{
	double fractionCompleted = progress.fractionCompleted;
	int64_t completedUnitCount = progress.completedUnitCount;
	int64_t totalUnitCount = progress.totalUnitCount;
	SendDownload( "progress", assetPack, ^( lua_State *L ) {
		lua_createtable( L, 0, 3 );
		lua_pushnumber( L, fractionCompleted );
		lua_setfield( L, -2, "fractionCompleted" );
		lua_pushnumber( L, completedUnitCount );
		lua_setfield( L, -2, "completedUnitCount" );
		lua_pushnumber( L, totalUnitCount );
		lua_setfield( L, -2, "totalUnitCount" );
		lua_setfield( L, -2, "progress" );
	} );
}

- (void)downloadOfAssetPackFinished:(BAAssetPack *)assetPack
{
	SendDownload( "finished", assetPack, nil );
}

- (void)downloadOfAssetPack:(BAAssetPack *)assetPack failedWithError:(NSError *)error
{
	SendDownload( "failed", assetPack, ^( lua_State *L ) {
		PushError( L, error );
		lua_setfield( L, -2, "error" );
	} );
}

@end

// The manager holds its delegate weakly, so this keeps it.
static id sDownloadDelegate;

// backend.setDelegate( handler )
static int SetDelegate( lua_State *L ) API_AVAILABLE( ios( 26.0 ) )
{
	luaL_checktype( L, 1, LUA_TFUNCTION );
	luaL_unref( L, LUA_REGISTRYINDEX, sDownloadHandler.ref );
	sDownloadHandler = Reference( L, 1 );
	if ( ! sDownloadDelegate ) { sDownloadDelegate = [[PluginBackgroundAssetsDownloadDelegate alloc] init]; }
	BAAssetPackManager.sharedManager.delegate = sDownloadDelegate;
	return 0;
}

// The manager calls (docs/backend.rst), each behind the iOS version of its Objective-C counterpart

// backend.getAssetPack( id, done )
static int GetAssetPack( lua_State *L ) API_AVAILABLE( ios( 26.0 ) )
{
	NSString *assetPackId = CheckNSString( L, 1 );
	LuaCallback done = ReferenceDone( L );
	[BAAssetPackManager.sharedManager getAssetPackWithIdentifier:assetPackId
		completionHandler:^( BAAssetPack *pack, NSError *error ) {
			Finish( done, error, ^( lua_State *coronaL ) {
				PushAssetPack( coronaL, pack );
				return 1;
			} );
		}];
	return 0;
}

// backend.getAllAssetPacks( done )
static int GetAllAssetPacks( lua_State *L ) API_AVAILABLE( ios( 26.0 ) )
{
	LuaCallback done = ReferenceDone( L );
	[BAAssetPackManager.sharedManager getAllAssetPacksWithCompletionHandler:^( NSSet *packs, NSError *error ) {
		Finish( done, error, ^( lua_State *coronaL ) {
			PushAssetPacks( coronaL, packs );
			return 1;
		} );
	}];
	return 0;
}

// backend.getStatusOfAssetPack( id, done )
static int GetStatusOfAssetPack( lua_State *L ) API_AVAILABLE( ios( 26.0 ) )
{
	NSString *assetPackId = CheckNSString( L, 1 );
	LuaCallback done = ReferenceDone( L );
	[BAAssetPackManager.sharedManager getStatusOfAssetPackWithIdentifier:assetPackId
		completionHandler:^( BAAssetPackStatus status, NSError *error ) {
			FinishWithStatus( done, status, error );
		}];
	return 0;
}

// backend.ensureLocalAvailability( id, requireLatestVersion, done )
static int EnsureLocalAvailability( lua_State *L ) API_AVAILABLE( ios( 26.0 ) )
{
	NSArray *ids = @[CheckNSString( L, 1 )];
	BOOL requireLatestVersion = lua_toboolean( L, 2 );
	LuaCallback done = ReferenceDone( L );
	ResolveAssetPacks( ids, ^( NSSet *packs, NSError *error ) {
		if ( error ) { FinishWithTrue( done, error ); return; }
		BAAssetPackManager *manager = BAAssetPackManager.sharedManager;
		void (^handler)( NSError * ) = ^( NSError *ensureError ) { FinishWithTrue( done, ensureError ); };
		if ( ! requireLatestVersion ) {
			[manager ensureLocalAvailabilityOfAssetPack:packs.anyObject completionHandler:handler];
		} else if ( @available( iOS 26.4, * ) ) {
			[manager ensureLocalAvailabilityOfAssetPack:packs.anyObject requireLatestVersion:YES completionHandler:handler];
		} else {
			Call( done, YES, ^( lua_State *coronaL ) {
				lua_pushnil( coronaL );
				PushUnsupported( coronaL, "ensureLocalAvailability with requireLatestVersion" );
				return 2;
			} );
		}
	} );
	return 0;
}

// backend.checkForUpdates( done )
static int CheckForUpdates( lua_State *L ) API_AVAILABLE( ios( 26.0 ) )
{
	LuaCallback done = ReferenceDone( L );
	[BAAssetPackManager.sharedManager checkForUpdatesWithCompletionHandler:^( NSSet *updating, NSSet *removed,
		NSError *error ) {
		Finish( done, error, ^( lua_State *coronaL ) {
			lua_createtable( coronaL, 0, 2 );
			PushStrings( coronaL, updating );
			lua_setfield( coronaL, -2, "updatingIdentifiers" );
			PushStrings( coronaL, removed );
			lua_setfield( coronaL, -2, "removedIdentifiers" );
			return 1;
		} );
	}];
	return 0;
}

// The plugin's removes in flight, which path lookups wait for (D12)
static dispatch_group_t RemovesInFlight( void )
{
	static dispatch_group_t removes;
	static dispatch_once_t once;
	dispatch_once( &once, ^{ removes = dispatch_group_create(); } );
	return removes;
}

// backend.removeAssetPack( id, done )
static int RemoveAssetPack( lua_State *L ) API_AVAILABLE( ios( 26.0 ) )
{
	NSString *assetPackId = CheckNSString( L, 1 );
	LuaCallback done = ReferenceDone( L );
	dispatch_group_t removes = RemovesInFlight();
	dispatch_group_enter( removes );
	[BAAssetPackManager.sharedManager removeAssetPackWithIdentifier:assetPackId completionHandler:^( NSError *error ) {
		// Before the hop to the main thread, where a path lookup may be waiting for this remove
		dispatch_group_leave( removes );
		FinishWithTrue( done, error );
	}];
	return 0;
}

// backend.getStatusRelativeToAssetPack( id, done )
static int GetStatusRelativeToAssetPack( lua_State *L ) API_AVAILABLE( ios( 26.4 ) )
{
	NSArray *ids = @[CheckNSString( L, 1 )];
	LuaCallback done = ReferenceDone( L );
	ResolveAssetPacks( ids, ^( NSSet *packs, NSError *error ) {
		if ( error ) { FinishWithStatus( done, 0, error ); return; }
		[BAAssetPackManager.sharedManager getStatusRelativeToAssetPack:packs.anyObject
			completionHandler:^( BAAssetPackStatus status, NSError *statusError ) {
				FinishWithStatus( done, status, statusError );
			}];
	} );
	return 0;
}

// backend.getLocalStatusOfAssetPack( id, done )
static int GetLocalStatusOfAssetPack( lua_State *L ) API_AVAILABLE( ios( 26.4 ) )
{
	NSString *assetPackId = CheckNSString( L, 1 );
	LuaCallback done = ReferenceDone( L );
	[BAAssetPackManager.sharedManager getLocalStatusOfAssetPackWithIdentifier:assetPackId
		completionHandler:^( BAAssetPackStatus status ) {
			FinishWithStatus( done, status, nil );
		}];
	return 0;
}

// backend.assetPackIsAvailableLocally( id )
static int AssetPackIsAvailableLocally( lua_State *L ) API_AVAILABLE( ios( 26.4 ) )
{
	lua_pushboolean( L, [BAAssetPackManager.sharedManager assetPackIsAvailableLocallyWithIdentifier:CheckNSString( L, 1 )] );
	return 1;
}

// backend.getManifest( done )
static int GetManifest( lua_State *L ) API_AVAILABLE( ios( 27.0 ) )
{
	LuaCallback done = ReferenceDone( L );
	[BAAssetPackManager.sharedManager getManifestWithCompletionHandler:^( BAAssetPackManifest *manifest,
		NSError *error ) {
		Finish( done, error, ^( lua_State *coronaL ) {
			PushManifest( coronaL, manifest );
			return 1;
		} );
	}];
	return 0;
}

// backend.ensureLocalAvailabilityOfAssetPacks( ids, requireLatestVersions, done )
static int EnsureLocalAvailabilityOfAssetPacks( lua_State *L ) API_AVAILABLE( ios( 27.0 ) )
{
	NSArray *ids = CheckNSStrings( L, 1 );
	BOOL requireLatestVersions = lua_toboolean( L, 2 );
	LuaCallback done = ReferenceDone( L );
	ResolveAssetPacks( ids, ^( NSSet *packs, NSError *error ) {
		if ( error ) { FinishWithTrue( done, error ); return; }
		[BAAssetPackManager.sharedManager ensureLocalAvailabilityOfAssetPacks:packs
			requireLatestVersions:requireLatestVersions completionHandler:^( NSError *ensureError ) {
				FinishWithTrue( done, ensureError );
			}];
	} );
	return 0;
}

// backend.getLocallyAvailableLanguages( done )
static int GetLocallyAvailableLanguages( lua_State *L ) API_AVAILABLE( ios( 27.0 ) )
{
	LuaCallback done = ReferenceDone( L );
	[BAAssetPackManager.sharedManager getLocallyAvailableLanguagesWithCompletionHandler:^( NSArray *languages ) {
		Finish( done, nil, ^( lua_State *coronaL ) {
			PushStrings( coronaL, languages );
			return 1;
		} );
	}];
	return 0;
}

// backend.reconcilePreferredLanguages( done )
static int ReconcilePreferredLanguages( lua_State *L ) API_AVAILABLE( ios( 27.0 ) )
{
	LuaCallback done = ReferenceDone( L );
	[BAAssetPackManager.sharedManager reconcilePreferredLanguagesWithCompletionHandler:^( NSError *error ) {
		FinishWithTrue( done, error );
	}];
	return 0;
}

// backend.getResolvedLanguage()
static int GetResolvedLanguage( lua_State *L ) API_AVAILABLE( ios( 27.0 ) )
{
	PushNSString( L, BAAssetPackManager.sharedManager.resolvedLanguage );
	return 1;
}

// backend.setResolvedLanguage( language or nil )
static int SetResolvedLanguage( lua_State *L ) API_AVAILABLE( ios( 27.0 ) )
{
	const char *language = luaL_optstring( L, 1, NULL );
	BAAssetPackManager.sharedManager.resolvedLanguage = language ? [NSString stringWithUTF8String:language] : nil;
	return 0;
}

// The path primitives (docs/backend.rst). The front makes the pack and file checks (D11) through
// assetPackIsAvailableLocally, the removed-pack record and fileExists; the lookups wait out the transient 513 (D12).

static BOOL Is513( NSError *error )
{
	return [error.domain isEqualToString:NSCocoaErrorDomain] && error.code == NSFileWriteNoPermissionError; // 513
}

// Runs lookup, one of Apple's path lookups for path, once the plugin's removes in flight have completed (waiting up
// to kRemoveWaitMilliseconds), and again on NSCocoaErrorDomain 513 up to kRetriesOn513 times, kRetrySleepMilliseconds
// apart, within kRetryBudgetMilliseconds. Logs every 513 it sees. Returns nil when lookup succeeded, else its error.
static NSError *LookUp( NSString *path, BOOL (^lookup)( NSError **error ) )
{
	dispatch_time_t removeDeadline = dispatch_time( DISPATCH_TIME_NOW, kRemoveWaitMilliseconds * NSEC_PER_MSEC );
	dispatch_group_wait( RemovesInFlight(), removeDeadline );
	NSProcessInfo *process = [NSProcessInfo processInfo];
	NSTimeInterval deadline = process.systemUptime + kRetryBudgetMilliseconds / 1000;
	for ( int retry = 1; ; retry++ ) {
		NSError *error = nil;
		if ( lookup( &error ) ) { return nil; }
		if ( ! Is513( error ) ) { return error; }
		BOOL canRetry = retry <= kRetriesOn513 && process.systemUptime + kRetrySleepMilliseconds / 1000.0 < deadline;
		if ( ! canRetry ) {
			NSLog( @"plugin.backgroundAssets: NSCocoaErrorDomain 513 looking up %@, giving up", path );
			return error;
		}
		NSLog( @"plugin.backgroundAssets: NSCocoaErrorDomain 513 looking up %@, retry %d of %d", path, retry,
			kRetriesOn513 );
		usleep( kRetrySleepMilliseconds * 1000 );
	}
}

// backend.urlForPath( path, language )
static int UrlForPath( lua_State *L ) API_AVAILABLE( ios( 26.0 ) )
{
	NSString *path = CheckNSString( L, 1 );
	NSString *language = OptNSString( L, 2 );
	__block NSURL *url = nil;
	NSError *error = LookUp( path, ^BOOL( NSError **lookupError ) {
		BAAssetPackManager *manager = BAAssetPackManager.sharedManager;
		if ( @available( iOS 27.0, * ) ) {
			if ( language ) {
				url = [manager URLForPath:path asLocalizedForLanguage:language error:lookupError];
				return url != nil;
			}
		}
		url = [manager URLForPath:path error:lookupError];
		return url != nil;
	} );
	return PushResult( L, error, ^( lua_State *resultL ) {
		PushNSString( resultL, url.path );
		return 1;
	} );
}

// backend.fileExists( file )
static int FileExists( lua_State *L ) API_AVAILABLE( ios( 26.0 ) )
{
	lua_pushboolean( L, [NSFileManager.defaultManager fileExistsAtPath:CheckNSString( L, 1 )] );
	return 1;
}

// backend.contentsAtPath( path, assetPackId, language )
static int ContentsAtPath( lua_State *L ) API_AVAILABLE( ios( 26.0 ) )
{
	NSString *path = CheckNSString( L, 1 );
	NSString *assetPackId = OptNSString( L, 2 );
	NSString *language = OptNSString( L, 3 );
	__block NSData *contents = nil;
	NSError *error = LookUp( path, ^BOOL( NSError **lookupError ) {
		BAAssetPackManager *manager = BAAssetPackManager.sharedManager;
		if ( @available( iOS 27.0, * ) ) {
			if ( language ) {
				contents = [manager contentsAtPath:path asLocalizedForLanguage:language options:0 error:lookupError];
				return contents != nil;
			}
		}
		contents = [manager contentsAtPath:path searchingInAssetPackWithIdentifier:assetPackId options:0
			error:lookupError];
		return contents != nil;
	} );
	return PushResult( L, error, ^( lua_State *resultL ) {
		lua_pushlstring( resultL, contents.bytes, contents.length );
		return 1;
	} );
}

// Pushes the environment the io library gives its own functions and the files it opens: its __close is what
// file:close() and the collector call. Returns NO, with nothing pushed, when there is no such io library.
static BOOL PushIoEnvironment( lua_State *L )
{
	int top = lua_gettop( L );
	lua_getglobal( L, "io" );
	if ( lua_istable( L, -1 ) ) {
		lua_getfield( L, -1, "type" );
		lua_getfenv( L, -1 ); // nil unless io.type is a function
		if ( lua_istable( L, -1 ) ) {
			lua_getfield( L, -1, "__close" );
			if ( lua_iscfunction( L, -1 ) ) {
				lua_pop( L, 1 );
				lua_replace( L, top + 1 );
				lua_settop( L, top + 1 );
				return YES;
			}
		}
	}
	lua_settop( L, top );
	return NO;
}

// Pushes an open Lua 5.1 file on fd, as io.open gives one (D14.10). When it cannot, it closes fd, pushes nothing and
// returns the error.
static NSError *PushFile( lua_State *L, int fd )
{
	luaL_getmetatable( L, LUA_FILEHANDLE );
	if ( lua_isnil( L, -1 ) || ! PushIoEnvironment( L ) ) {
		lua_pop( L, 1 );
		close( fd );
		return PluginError( kUnsupportedCode, @"fileForPath needs Lua's io library" );
	}
	FILE **file = (FILE **)lua_newuserdata( L, sizeof( FILE * ) );
	*file = NULL; // a closed file until fdopen succeeds
	lua_insert( L, -3 );
	lua_setfenv( L, -3 );
	lua_setmetatable( L, -2 );
	*file = fdopen( fd, "r" );
	if ( ! *file ) {
		NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
		close( fd );
		lua_pop( L, 1 );
		return error;
	}
	return nil;
}

// backend.fileForPath( path, assetPackId, language )
static int FileForPath( lua_State *L ) API_AVAILABLE( ios( 26.0 ) )
{
	NSString *path = CheckNSString( L, 1 );
	NSString *assetPackId = OptNSString( L, 2 );
	NSString *language = OptNSString( L, 3 );
	__block int fd = -1;
	NSError *error = LookUp( path, ^BOOL( NSError **lookupError ) {
		BAAssetPackManager *manager = BAAssetPackManager.sharedManager;
		if ( @available( iOS 27.0, * ) ) {
			if ( language ) {
				fd = [manager fileDescriptorForPath:path asLocalizedForLanguage:language error:lookupError];
				return fd >= 0;
			}
		}
		fd = [manager fileDescriptorForPath:path searchingInAssetPackWithIdentifier:assetPackId error:lookupError];
		return fd >= 0;
	} );
	if ( ! error ) { error = PushFile( L, fd ); }
	return PushResult( L, error, ^( lua_State *resultL ) { return 1; } ); // the file is on top already
}

// Pushes system.CachesDirectory and returns the path system.pathForFile gives name in it.
static NSString *PathInCachesDirectory( lua_State *L, NSString *name )
{
	lua_getglobal( L, "system" );
	lua_getfield( L, -1, "CachesDirectory" );
	lua_getfield( L, -2, "pathForFile" );
	PushNSString( L, name );
	lua_pushvalue( L, -3 );
	lua_call( L, 2, 1 );
	NSString *path = lua_isstring( L, -1 ) ? [NSString stringWithUTF8String:lua_tostring( L, -1 )] : nil;
	lua_pop( L, 1 );
	lua_remove( L, -2 );
	return path;
}

// Makes link a symbolic link to target, unless it is one already.
static NSError *EnsureLink( NSString *link, NSString *target )
{
	NSFileManager *files = NSFileManager.defaultManager;
	if ( [[files destinationOfSymbolicLinkAtPath:link error:nil] isEqualToString:target] ) { return nil; }
	[files removeItemAtPath:link error:nil]; // a link to an old target, if any
	NSError *error = nil;
	BOOL isLinked = [files createDirectoryAtPath:link.stringByDeletingLastPathComponent withIntermediateDirectories:YES
		attributes:nil error:&error] && [files createSymbolicLinkAtPath:link withDestinationPath:target error:&error];
	return isLinked ? nil : error;
}

// backend.link( path, file ): one link per namespace root, <kLinksFolder>/<the root's name> under the directory
// system.CachesDirectory resolves to, pointing at the root, the folder file is at path in. Checked on every call, so
// it is created when missing (the OS purges caches) and replaced when the root moves. Returns the file through that
// link, and system.CachesDirectory.
static int Link( lua_State *L ) API_AVAILABLE( ios( 26.0 ) )
{
	NSString *path = CheckNSString( L, 1 );
	NSString *file = CheckNSString( L, 2 );
	NSString *suffix = [@"/" stringByAppendingString:path];
	if ( ! [file hasSuffix:suffix] ) {
		return PushResult( L, PluginError( kInvalidArgumentCode, @"pathForFile needs a plain relative path" ), nil );
	}
	NSString *root = [file substringToIndex:file.length - suffix.length];
	NSString *linkName = [kLinksFolder stringByAppendingPathComponent:root.lastPathComponent];
	NSString *link = PathInCachesDirectory( L, linkName );
	NSError *error = link ? EnsureLink( link, root )
		: PluginError( kUnsupportedCode, @"system.CachesDirectory has no path" );
	if ( error ) {
		lua_pop( L, 1 );
		return PushResult( L, error, nil );
	}
	PushNSString( L, [linkName stringByAppendingPathComponent:path] );
	lua_insert( L, -2 );
	return 2;
}

// backend.unlinkAssetPack( id ): a namespace root's link serves every pack in that root, so no link serves only id.
static int UnlinkAssetPack( lua_State *L ) API_AVAILABLE( ios( 26.0 ) )
{
	return 0;
}

// backend.loadRemovedAssetPacks()
static int LoadRemovedAssetPacks( lua_State *L )
{
	PushStrings( L, [NSUserDefaults.standardUserDefaults stringArrayForKey:kRemovedAssetPacksKey] );
	return 1;
}

// backend.saveRemovedAssetPacks( ids )
static int SaveRemovedAssetPacks( lua_State *L )
{
	[NSUserDefaults.standardUserDefaults setObject:CheckNSStrings( L, 1 ) forKey:kRemovedAssetPacksKey];
	return 0;
}

// Sets the manager calls this OS has on the table on top of the stack.
static void SetManagerCalls( lua_State *L )
{
	if ( ! ApiVersion() ) { return; }
	if ( @available( iOS 26.0, * ) ) {
		const luaL_Reg kCalls[] =
		{
			{ "setDelegate", SetDelegate },
			{ "getAssetPack", GetAssetPack },
			{ "getAllAssetPacks", GetAllAssetPacks },
			{ "getStatusOfAssetPack", GetStatusOfAssetPack },
			{ "ensureLocalAvailability", EnsureLocalAvailability },
			{ "checkForUpdates", CheckForUpdates },
			{ "removeAssetPack", RemoveAssetPack },
			{ "urlForPath", UrlForPath },
			{ "fileExists", FileExists },
			{ "contentsAtPath", ContentsAtPath },
			{ "fileForPath", FileForPath },
			{ "link", Link },
			{ "unlinkAssetPack", UnlinkAssetPack },
			{ NULL, NULL }
		};
		luaL_register( L, NULL, kCalls );
	}
	if ( @available( iOS 26.4, * ) ) {
		const luaL_Reg kCalls[] =
		{
			{ "getStatusRelativeToAssetPack", GetStatusRelativeToAssetPack },
			{ "getLocalStatusOfAssetPack", GetLocalStatusOfAssetPack },
			{ "assetPackIsAvailableLocally", AssetPackIsAvailableLocally },
			{ NULL, NULL }
		};
		luaL_register( L, NULL, kCalls );
	}
	if ( @available( iOS 27.0, * ) ) {
		const luaL_Reg kCalls[] =
		{
			{ "getManifest", GetManifest },
			{ "ensureLocalAvailabilityOfAssetPacks", EnsureLocalAvailabilityOfAssetPacks },
			{ "getLocallyAvailableLanguages", GetLocallyAvailableLanguages },
			{ "reconcilePreferredLanguages", ReconcilePreferredLanguages },
			{ "getResolvedLanguage", GetResolvedLanguage },
			{ "setResolvedLanguage", SetResolvedLanguage },
			{ NULL, NULL }
		};
		luaL_register( L, NULL, kCalls );
	}
}

static void PushBackend( lua_State *L )
{
	const luaL_Reg kFunctions[] =
	{
		{ "info", Info },
		{ "defer", Defer },
		{ "loadRemovedAssetPacks", LoadRemovedAssetPacks },
		{ "saveRemovedAssetPacks", SaveRemovedAssetPacks },
		{ NULL, NULL }
	};

	lua_newtable( L );
	luaL_register( L, NULL, kFunctions );
	SetManagerCalls( L );
}

CORONA_EXPORT int luaopen_plugin_backgroundAssets( lua_State *L )
{
	if ( luaL_loadbuffer( L, (const char *)kFront, sizeof( kFront ), kFrontChunkName ) ) {
		return lua_error( L );
	}
	PushBackend( L );
	lua_call( L, 1, 1 ); // the front returns the library table
	return 1;
}
