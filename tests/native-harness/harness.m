// The native harness's side of the plugin (tests/native-harness/suite.sh): the Corona symbols the plugin calls, a fake
// Background Assets manager and a fake user defaults, both swizzled in, and luaopen_harness, the Lua module that drives
// the fakes and observes the plugin.

#import <Foundation/Foundation.h>
#import <BackgroundAssets/BackgroundAssets.h>
#import <objc/runtime.h>

#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

#include "lua.h"
#include "lauxlib.h"

// Corona's symbols: Solar2D's lua has one Lua state and no main-queue turn, so callbacks queued there never run.

__attribute__((visibility("default"))) lua_State *CoronaLuaGetCoronaThread( lua_State *coroutine )
{
	return coroutine;
}

__attribute__((visibility("default"))) int CoronaLuaDoCall( lua_State *L, int narg, int nresults )
{
	return lua_pcall( L, narg, nresults, 0 );
}

// The fake manager's script

static NSString *sRoot; // the folder lookups find paths in
static NSMutableArray *sOutcomes; // the outcome of each next lookup: 0 ok, else an NSCocoaErrorDomain code
static NSInteger sRestOutcome; // the outcome once sOutcomes is empty
static useconds_t sLookupMicroseconds; // how long each lookup takes
static int sLookupCount;
static BOOL sBadFd; // fileDescriptorForPath gives an fd that is not open
static int sLastFd = -1;
static int64_t sRemoveMilliseconds = -1; // when a remove completes, or never when negative

static BOOL Lookup( NSError **error )
{
	sLookupCount++;
	usleep( sLookupMicroseconds );
	NSInteger outcome = sRestOutcome;
	if ( sOutcomes.count ) {
		outcome = [sOutcomes[0] integerValue];
		[sOutcomes removeObjectAtIndex:0];
	}
	if ( outcome && error ) { *error = [NSError errorWithDomain:NSCocoaErrorDomain code:outcome userInfo:nil]; }
	return ! outcome;
}

// What +[BAAssetPackManager sharedManager] gives: the selectors the path calls send, answered from the script.
@interface HarnessManager : NSObject
@end

@implementation HarnessManager

- (NSURL *)URLForPath:(NSString *)path error:(NSError **)error
{
	return Lookup( error ) ? [NSURL fileURLWithPath:[sRoot stringByAppendingPathComponent:path]] : nil;
}

- (int)fileDescriptorForPath:(NSString *)path searchingInAssetPackWithIdentifier:(NSString *)assetPackId
	error:(NSError **)error
{
	if ( ! Lookup( error ) ) { return -1; }
	sLastFd = sBadFd ? 1000 : open( [sRoot stringByAppendingPathComponent:path].fileSystemRepresentation, O_RDONLY );
	return sLastFd;
}

- (void)removeAssetPackWithIdentifier:(NSString *)assetPackId completionHandler:(void (^)( NSError * ))handler
{
	if ( sRemoveMilliseconds < 0 ) { return; }
	handler = [handler copy];
	dispatch_after( dispatch_time( DISPATCH_TIME_NOW, sRemoveMilliseconds * NSEC_PER_MSEC ),
		dispatch_get_global_queue( QOS_CLASS_DEFAULT, 0 ), ^{
			handler( nil );
			[handler release];
		} );
}

@end

// What +[NSUserDefaults standardUserDefaults] gives: values in memory, so nothing reaches the user's preferences.
@interface HarnessDefaults : NSUserDefaults
@end

@implementation HarnessDefaults
{
	NSMutableDictionary *_values;
}

- (id)objectForKey:(NSString *)key
{
	return _values[key];
}

- (void)setObject:(id)value forKey:(NSString *)key
{
	if ( ! _values ) { _values = [[NSMutableDictionary alloc] init]; }
	_values[key] = value;
}

@end

static id sManager;
static id sDefaults;

static id SharedManager( id self, SEL _cmd )
{
	return sManager;
}

static id StandardUserDefaults( id self, SEL _cmd )
{
	return sDefaults;
}

static void Swizzle( Class cls, SEL selector, IMP replacement )
{
	method_setImplementation( class_getClassMethod( cls, selector ), replacement );
}

// harness.lookups( outcomes, rest, milliseconds ): the next lookups' outcomes (0 ok, else an NSCocoaErrorDomain
// code), the outcome after them, and how long each takes; resets the lookup count
static int Lookups( lua_State *L )
{
	luaL_checktype( L, 1, LUA_TTABLE );
	[sOutcomes removeAllObjects];
	for ( int i = 1; i <= (int)lua_objlen( L, 1 ); i++ ) {
		lua_rawgeti( L, 1, i );
		[sOutcomes addObject:@( luaL_checkinteger( L, -1 ) )];
		lua_pop( L, 1 );
	}
	sRestOutcome = luaL_optinteger( L, 2, 0 );
	sLookupMicroseconds = (useconds_t)( luaL_optnumber( L, 3, 0 ) * 1000 );
	sLookupCount = 0;
	return 0;
}

// harness.lookupCount()
static int LookupCount( lua_State *L )
{
	lua_pushinteger( L, sLookupCount );
	return 1;
}

// harness.setRoot( folder )
static int SetRoot( lua_State *L )
{
	[sRoot release];
	sRoot = [[NSString alloc] initWithUTF8String:luaL_checkstring( L, 1 )];
	return 0;
}

// harness.badFd( on )
static int BadFd( lua_State *L )
{
	sBadFd = lua_toboolean( L, 1 );
	return 0;
}

// harness.lastFd(): the fd the last fileDescriptorForPath gave
static int LastFd( lua_State *L )
{
	lua_pushinteger( L, sLastFd );
	return 1;
}

// harness.isOpen( fd )
static int IsOpen( lua_State *L )
{
	lua_pushboolean( L, fcntl( (int)luaL_checkinteger( L, 1 ), F_GETFD ) != -1 );
	return 1;
}

// harness.removeCompletesAfter( milliseconds ): a later remove completes that long after it is made; never when negative
static int RemoveCompletesAfter( lua_State *L )
{
	sRemoveMilliseconds = luaL_checkinteger( L, 1 );
	return 0;
}

// harness.uptime(): milliseconds
static int Uptime( lua_State *L )
{
	lua_pushnumber( L, [NSProcessInfo processInfo].systemUptime * 1000 );
	return 1;
}

// harness.logTo( file ): stderr, where NSLog writes, goes to file
static int LogTo( lua_State *L )
{
	lua_pushboolean( L, freopen( luaL_checkstring( L, 1 ), "w", stderr ) != NULL );
	return 1;
}

// harness.readLink( path ): the link's target and inode, or nil when path is no symbolic link
static int ReadLink( lua_State *L )
{
	const char *path = luaL_checkstring( L, 1 );
	char target[PATH_MAX];
	struct stat info;
	ssize_t length = readlink( path, target, sizeof( target ) );
	if ( length < 0 || lstat( path, &info ) ) { return 0; }
	lua_pushlstring( L, target, (size_t)length );
	lua_pushnumber( L, (lua_Number)info.st_ino );
	return 2;
}

static int sTopAtReturn;

// The return hook runs on the returning function's frame, so lua_gettop there is that function's stack.
static void ReturnHook( lua_State *L, lua_Debug *ar )
{
	if ( ar->event != LUA_HOOKRET ) { return; }
	int top = lua_gettop( L );
	lua_getinfo( L, "f", ar );
	lua_getfield( L, LUA_REGISTRYINDEX, "harness.watched" );
	if ( lua_rawequal( L, -1, -2 ) ) { sTopAtReturn = top; }
	lua_pop( L, 2 );
}

// harness.topAtReturn( fn, ... ): the size of fn's stack when it returns, then fn's results
static int TopAtReturn( lua_State *L )
{
	luaL_checktype( L, 1, LUA_TFUNCTION );
	int base = lua_gettop( L );
	lua_pushvalue( L, 1 );
	lua_setfield( L, LUA_REGISTRYINDEX, "harness.watched" );
	sTopAtReturn = -1;
	lua_sethook( L, ReturnHook, LUA_MASKRET, 0 );
	lua_call( L, base - 1, LUA_MULTRET );
	lua_sethook( L, NULL, 0, 0 );
	lua_pushinteger( L, sTopAtReturn );
	lua_insert( L, 1 );
	return lua_gettop( L );
}

__attribute__((visibility("default"))) int luaopen_harness( lua_State *L )
{
	sOutcomes = [[NSMutableArray alloc] init];
	sManager = [[HarnessManager alloc] init];
	sDefaults = [[HarnessDefaults alloc] initWithSuiteName:nil];
	Swizzle( [BAAssetPackManager class], @selector( sharedManager ), (IMP)SharedManager );
	Swizzle( [NSUserDefaults class], @selector( standardUserDefaults ), (IMP)StandardUserDefaults );
	const luaL_Reg kFunctions[] =
	{
		{ "lookups", Lookups },
		{ "lookupCount", LookupCount },
		{ "setRoot", SetRoot },
		{ "badFd", BadFd },
		{ "lastFd", LastFd },
		{ "isOpen", IsOpen },
		{ "removeCompletesAfter", RemoveCompletesAfter },
		{ "uptime", Uptime },
		{ "logTo", LogTo },
		{ "readLink", ReadLink },
		{ "topAtReturn", TopAtReturn },
		{ NULL, NULL }
	};
	lua_newtable( L );
	luaL_register( L, NULL, kFunctions );
	return 1;
}
