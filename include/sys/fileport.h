#ifndef _SYS_FILEPORT_H
#define _SYS_FILEPORT_H

#include <mach/mach.h>
#include <sys/cdefs.h>

__BEGIN_DECLS

typedef mach_port_t fileport_t;

kern_return_t fileport_makeport(int fd, fileport_t *fileport);
int fileport_makefd(fileport_t fileport);

__END_DECLS

#endif /* _SYS_FILEPORT_H */
