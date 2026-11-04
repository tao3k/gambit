/* Actual private diagnostic consumers, isolated from the production archive:
 * DEBUG changes C layouts. Only output and fatal-delivery sinks are controlled;
 * allocation/scanning/diagnostic decisions are the real mem.c definitions.
 * This does not qualify the whole debug VM or native fatal cleanup. */
#include <stdarg.h>
#include <stdio.h>
#include "mem.c"

___global_state_struct ___gstate0;
static char report[32768];
static size_t used;
static int expect_fatal;

int ___printf(const char *format, ...)
{
  va_list ap;
  int n;
  va_start(ap,format);
  n=vsnprintf(report+used,sizeof(report)-used,format,ap);
  va_end(ap);
  if(n<0 || (size_t)n>=sizeof(report)-used) exit(80);
  used+=(size_t)n;
  return n;
}

void ___fatal_error(char **messages)
{
  if(expect_fatal && messages && messages[0] &&
     strstr(report,"W7 (carrier P0)") && strstr(report,"line 123") &&
     strstr(report,"reference counted object") && !strstr(report,"line 999")) {
    puts("COLLECTOR-DIAGNOSTIC-FATAL-PASS selected-worker");
    exit(73);
  }
  fputs(report,stderr);
  exit(81);
}

#define CHECK(x) do { if(!(x)) {fprintf(stderr,"collector-diagnostics:%d: %s\n%s",__LINE__,#x,report);return 1;} } while(0)

int main(int argc,char **argv)
{
  static ___virtual_machine_state_struct vm;
  static ___rc_domain domain;
  static ___root_round round;
  static ___collector_worker selected,decoy;
  static ___msections map;
  ___processor_state ps=___PSTATE_FROM_PROCESSOR_ID(0,&vm);
  ___msection *section=calloc(1,___sizeof_msection(___MSECTION_SIZE));
  ___SCMOBJ obj;
  char needle[128];
  CHECK(section!=0);
  map.max_nb_sections=map.nb_sections=1;
  map.head=map.tail=map.sections[0]=section;
  vm.mem.the_msections_=&map;
#ifndef ___SINGLE_VM
  ps->vmstate=&vm;
#endif
  ps->mem.rc_domain_=&domain;domain.round=&round;
  selected.vm=&vm;selected.carrier=ps;selected.id=7;
  selected.reference_location_=IN_RC;selected.mark_array_call_line_=123;
  selected.scan_ptr_=section->base+7;
  selected.arena.cursor=section->base+9;selected.arena.limit=section->base+20;
  decoy.vm=&vm;decoy.carrier=ps;decoy.id=99;
  decoy.reference_location_=IN_REGISTER;decoy.mark_array_call_line_=999;
  decoy.scan_ptr_=section->base+3;
  ps->collector=&decoy; /* May not override the actual scanning worker. */
  ps->mem.tospace_offset_=0; /* Deliberately stale carrier projection. */
  round.collection.destination_offset=___MSECTION_SIZE>>1;
  section->base[0]=___MAKE_HD_WORDS(1,___sVECTOR);
  section->base[1]=___FIX(0);
  obj=___TAG(section->base+1,___tSUBTYPED);
  validate_old_obj(&selected,obj); /* Round says source, carrier says tospace. */
  dump_memory_map(&selected);
  snprintf(needle,sizeof(needle),"scan_ptr             = %p",selected.scan_ptr_);
  CHECK(strstr(report,needle)!=0);
  CHECK(strstr(report,"Memory map for worker 7")!=0);
  CHECK(strstr(report,"worker_arena_cursor")!=0);
  CHECK(selected.scan_ptr_==section->base+7 && ps->collector==&decoy);
  if(argc==2 && strcmp(argv[1],"--invalid")==0) {
    ___WORD *dest=section->base+round.collection.destination_offset;
    dest[0]=___MAKE_HD_WORDS(1,___sVECTOR);dest[1]=___FIX(0);
    expect_fatal=1;
    validate_old_obj(&selected,___TAG(dest+1,___tSUBTYPED));
    CHECK(0); /* The real diagnostic must reach its controlled fatal sink. */
  }
  free(section);
  puts("COLLECTOR-DIAGNOSTICS-PASS worker carrier-decoy round-offset arena");
  return 0;
}
