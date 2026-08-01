int		read_plist( const char *, size_t, const char *, CFDictionaryRef * );

/* plist keys */
#define DUTI_KEY_SETTINGS	CFSTR( "DUTISettings" )
#define DUTI_KEY_BUNDLEID	CFSTR( "DUTIBundleIdentifier" )
#define DUTI_KEY_UTI		CFSTR( "DUTIUniformTypeIdentifier" )
#define DUTI_KEY_ROLE		CFSTR( "DUTIRole" )
#define DUTI_KEY_URLSCHEME	CFSTR( "DUTIURLScheme" )
