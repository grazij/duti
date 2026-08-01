#include <CoreFoundation/CoreFoundation.h>

#include <sys/types.h>

#include "plist.h"

/*
 * reads from memory rather than a path so that one code path serves a file,
 * a directory member and standard input. label names the source in errors.
 */
    int
read_plist( const char *buf, size_t len, const char *label,
	CFDictionaryRef *dr )
{
    CFReadStreamRef	cfrs = NULL;
    CFDictionaryRef	cfdict = NULL;
    CFPropertyListFormat	fmt = kCFPropertyListXMLFormat_v1_0;
    CFStreamError	err;

    int			rc = 0;

    *dr = NULL;

    if ( buf == NULL ) {
	fprintf( stderr, "%s: no plist data\n", label );
	return( -1 );
    }

    if (( cfrs = CFReadStreamCreateWithBytesNoCopy( kCFAllocatorDefault,
			( const UInt8 * )buf, ( CFIndex )len,
			kCFAllocatorNull )) == NULL ) {
	fprintf( stderr, "%s: failed to create read stream\n", label );
	return( -1 );
    }
    if ( CFReadStreamOpen( cfrs ) == false ) {
	err = CFReadStreamGetError( cfrs );
	fprintf( stderr, "%s: failed to open read stream "
		"( domain %d, error %d )\n", label,
		( int )err.domain, ( int )err.error );
	rc = -1;
	goto cleanup;
    }

    if (( cfdict = CFPropertyListCreateWithStream( kCFAllocatorDefault, cfrs,
			0, kCFPropertyListImmutable, &fmt, NULL )) == NULL ) {
	fprintf( stderr, "%s: failed to read plist\n", label );
	rc = -1;
	goto cleanup;
    }

    if ( !CFPropertyListIsValid( cfdict, fmt )) {
	fprintf( stderr, "%s: invalid plist\n", label );
	CFRelease( cfdict );
	cfdict = NULL;
	rc = -1;
    }

cleanup:
    CFReadStreamClose( cfrs );
    CFRelease( cfrs );

    *dr = cfdict;

    return( rc );
}
