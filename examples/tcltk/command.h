/* Tcl command ownership. The caller supplies a valid owner-thread interpreter.
 * Runtime roots remain owned by Gambit RC/still objects; no separate registry. */
#ifndef ___TCLTK_COMMAND_H
#define ___TCLTK_COMMAND_H
#include <tcl.h>

/*
 * The routine scheme_call_cmd is called by Tcl when a Scheme
 * procedure is being called.  The client_data parameter points to a
 * reference counted object which contains a vector containing the
 * Scheme procedure to call (this indirection is required because the
 * Scheme procedure may be a MOVABLE object).  The parameters argc and
 * argv specify the arguments to pass to the Scheme procedure.  The
 * Scheme procedure receives these arguments as strings and must
 * return a string result or the value #f.
 */

char *tcltk_call ___P((___SCMOBJ vect, char **args),());

___HIDDEN int scheme_call_cmd
   ___P((ClientData client_data,
         Tcl_Interp *interp,
         int argc,
         const char **argv),
        (client_data,
         interp,
         argc,
         argv)
ClientData client_data;
Tcl_Interp *interp;
int argc;
const char **argv;)
{
  char *result = tcltk_call (___EXT(___data_rc) (___CAST(void*,client_data)),
                             ___CAST(char**,argv+1));

  /*
   * Propagate result to Tcl.
   */

  if (result == NULL)
    {
      Tcl_SetResult (interp,
                     "",
                     TCL_STATIC);
    }
  else
    {
      /*
       * The resulting C string was dynamically allocated by
       * Gambit's C interface.  We have to ensure it is
       * deallocated by a call to ___release_string by Tcl
       * when it no longer needs the string.
       */

      Tcl_SetResult (interp,
                     result,
                     ___CAST(Tcl_FreeProc*,___EXT(___release_string)));
    }

  return TCL_OK;
}

/*
 * The routine scheme_delete_cmd is called by Tcl when a Tcl command
 * bound to a Scheme procedure is being deleted.  The client_data
 * parameter points to a reference counted object which contains the
 * Scheme procedure.  This object needs to be released so that the
 * garbage collector can reclaim the Scheme procedure it contains.
 */

___HIDDEN void scheme_delete_cmd
   ___P((ClientData client_data),
        (client_data)
ClientData client_data;)
{
  ___EXT(___release_scmobj) (___EXT(___data_rc) (___CAST(void*,client_data)));
  ___EXT(___release_rc) (___CAST(void*,client_data));
}


/* The private RC record is the construction root before the first allocation.
 * On acceptance Tcl owns it through scheme_delete_cmd. On rejection this
 * function runs that same release path; Tcl has not acquired clientData. */
___HIDDEN ___BOOL scheme_create_cmd(___processor_state ___ps,
                                  Tcl_Interp *interp,
                                  const char *name,
                                  ___SCMOBJ proc)
{
  void *cd;
  ___SCMOBJ vect;
  if (interp == NULL) return 0;
  cd=___EXT(___alloc_rc)(___PSA(___ps) 0);
  if (cd == NULL) return 0;
  ___EXT(___set_data_rc)(cd,proc);
  vect=___EXT(___make_vector)(___ps,1,___FAL);
  if (___FIXNUMP(vect))
    { ___EXT(___release_rc)(cd); return 0; }
  ___VECTORELEM(vect,0)=___EXT(___data_rc)(cd);
  ___EXT(___set_data_rc)(cd,vect);
  if (Tcl_CreateCommand(interp,name,scheme_call_cmd,
                        ___CAST(ClientData,cd),scheme_delete_cmd) == NULL)
    { scheme_delete_cmd(___CAST(ClientData,cd)); return 0; }
  return 1;
}
#endif
