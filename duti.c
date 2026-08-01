/* duti: set default handlers for document types based on a settings file. */

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>

#include <sys/types.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "handler.h"

extern char		*duti_version;
extern int		nroles;
int			verbose = 0;

struct roles		rtm[] = {
    { "none",   kLSRolesNone },
    { "viewer", kLSRolesViewer },
    { "editor", kLSRolesEditor },
    { "shell",  kLSRolesShell },
    { "all",    kLSRolesAll },
};

    static void
usage( char *progname, FILE *out )
{
    fprintf( out, "usage: %s [ -hvV ] [ -c config ] [ -d uti ] [ -l uti ] "
		  "[ -u uti ]\n", progname );
    fprintf( out, "usage: %s -s bundle_id { uti | url_scheme } "
		  "[ role ]\n", progname );
    fprintf( out, "usage: %s { -e | -x } extension\n", progname );
    fprintf( out, "\n  -c config  read settings from config "
		  "( \"-\" reads standard input ).\n" );
    fprintf( out, "             without -c, duti reads the first of\n" );
    fprintf( out, "             $XDG_CONFIG_HOME/duti/config, "
		  "~/.config/duti/config,\n" );
    fprintf( out, "             or ~/.duti/config that exists.\n" );
}

/*
 * build dir + rest in buf and report whether the result exists.
 * returns 0 if the path would be truncated, so a too-long $HOME
 * can never produce a silently wrong path.
 */
    static int
config_exists( char *buf, size_t bufsz, const char *dir, const char *rest )
{
    struct stat		st;
    int			n;

    n = snprintf( buf, bufsz, "%s%s", dir, rest );
    if ( n < 0 || ( size_t )n >= bufsz ) {
	return( 0 );
    }

    return( stat( buf, &st ) == 0 );
}

/*
 * first existing config in XDG order. returns NULL if none is found,
 * which the caller treats as "nothing to do, show usage".
 */
    static char *
default_config_path( void )
{
    static char		cpath[ MAXPATHLEN ];
    char		*home, *xdg;

    xdg = getenv( "XDG_CONFIG_HOME" );
    if ( xdg != NULL && *xdg != '\0' ) {
	if ( config_exists( cpath, sizeof( cpath ), xdg, "/duti/config" )) {
	    return( cpath );
	}
    }

    if (( home = getenv( "HOME" )) == NULL || *home == '\0' ) {
	return( NULL );
    }

    /*
     * ~/.config is the XDG spec's own default for an unset or empty
     * XDG_CONFIG_HOME, so only consult it when the variable gave us
     * nothing.
     */
    if ( xdg == NULL || *xdg == '\0' ) {
	if ( config_exists( cpath, sizeof( cpath ), home,
			    "/.config/duti/config" )) {
	    return( cpath );
	}
    }

    if ( config_exists( cpath, sizeof( cpath ), home, "/.duti/config" )) {
	return( cpath );
    }

    return( NULL );
}

    int
main( int ac, char *av[] )
{
    struct stat		st;
    int			c, err = 0;
    int			set = 0;
    int			( *handler_f )( char * );
    char		*path = NULL;
    char		*cfgpath = NULL;
    char		*p;

    extern int		optind;
    extern char		*optarg;

    while (( c = getopt( ac, av, "c:d:e:l:hsu:Vvx:" )) != -1 ) {
	switch ( c ) {
	case 'c':	/* settings file, directory, or "-" for stdin */
	    cfgpath = optarg;
	    break;

	case 'd':	/* show default handler for UTI */
	    return( uti_handler_show( optarg, 0 ));

	case 'e':	/* UTI declarations for extension */
		return( duti_utis_for_extension( optarg ));

	case 'h':	/* help goes to stdout and exits successfully */
	    usage( av[ 0 ], stdout );
	    exit( 0 );

	default:
	    err++;
	    break;

	case 'l':	/* list all handlers for UTI */
	    return( uti_handler_show( optarg, 1 ));

	case 's':	/* set handler */
	    set = 1;
	    break;

	case 'u':	/* UTI declarations */
		return( duti_utis( optarg ));

	case 'V':	/* version */
	    printf( "%s\n", duti_version );
	    exit( 0 );

	case 'v':	/* verbose */
	    verbose = 1;
	    break;

	case 'x':	/* info for extension */
	    return( duti_default_app_for_extension( optarg ));
	}
    }

    nroles = sizeof( rtm ) / sizeof( rtm[ 0 ] );

    /*
     * -s takes its arguments from the command line, -c from a file.
     * this must be caught before the switch below, whose -s cases
     * return without ever consulting err.
     */
    if ( set && cfgpath != NULL ) {
	usage( av[ 0 ], stderr );
	exit( 1 );
    }

    switch (( ac - optind )) {
    case 0 :	/* -c, or the default config */
	if ( set ) {
	    err++;
	}
	break;

    case 2 :	/* set URL scheme handler */
	if ( set ) {
	    return( duti_handler_set( av[ optind ],
		    av[ optind + 1 ], NULL ));
	}
	err++;
	break;

    case 3 :	/* set UTI handler */
	if ( set ) {
	    return( duti_handler_set( av[ optind ],
		    av[ optind + 1 ], av[ optind + 2 ] ));
	}
	err++;
	break;

    default :	/* error, including the removed settings_path operand */
	err++;
	break;
    }

    if ( err ) {
	usage( av[ 0 ], stderr );
	exit( 1 );
    }

    if ( cfgpath != NULL ) {
	/*
	 * POSIX utility syntax guideline 13: "-" names standard input.
	 * fsethandler reads stdin when handed a NULL path.
	 */
	if ( strcmp( cfgpath, "-" ) == 0 ) {
	    return( fsethandler( NULL ));
	}
	path = cfgpath;
    } else if (( path = default_config_path()) == NULL ) {
	usage( av[ 0 ], stderr );
	exit( 1 );
    }

    /* by default, read from a FILE stream */
    handler_f = fsethandler;

    if ( stat( path, &st ) != 0 ) {
	fprintf( stderr, "stat %s: %s\n", path, strerror( errno ));
	exit( 2 );
    }
    switch ( st.st_mode & S_IFMT ) {
    case S_IFDIR:	/* directory of settings files */
	handler_f = dirsethandler;
	break;

    case S_IFREG:	/* settings file or plist */
	if (( p = strrchr( path, '.' )) != NULL ) {
	    p++;
	    if ( strcmp( p, "plist" ) == 0 ) {
		handler_f = psethandler;
	    }
	}
	break;

    default:
	fprintf( stderr, "%s: not a supported settings path\n", path );
	exit( 1 );
    }

    return( handler_f( path ));
}
