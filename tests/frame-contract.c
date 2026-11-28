/* Producer/consumer correspondence, using Scheme-generated plan fixtures and
 * independent integer/root enumeration. No GC or native lifecycle admission.
 */
#include <stdio.h>
#include "gambit.h"
#include "test-entry.h"

struct frame_case {
  int regs, kind, stored, link, actual, pattern, ofd;
  ___U32 chunks[8];
};
#include "frame-spec-fixtures.h"

/* Exercise the generated-code projections with a raw descriptor as test label.
 * Actual label access is separately compiled through the runtime consumers.
 */
#undef ___LABEL_DESCR_GET
#define ___LABEL_DESCR_GET(label) (label)
static unsigned int reads;
static ___WORD read_once (___WORD descriptor)
{
  reads++;
  return descriptor;
}

#define CHECK(x) do { if (!(x)) { \
  fprintf (stderr,"frame-contract:%d case=%lu: %s\n", \
           __LINE__,(unsigned long)i,#x); return 1; \
} } while (0)

GAMBIT_TEST_MAIN
{
  unsigned long i;
  unsigned int checked = 0;
  for (i=0; i<sizeof(cases)/sizeof(cases[0]); i++)
    {
      const struct frame_case *c = &cases[i];
      ___WORD table[9];
      ___WORD encoded;
      ___frame_descriptor frame;
      int actual, words, j;
      if (c->regs != ___NB_GVM_REGS) continue;
      actual = c->kind == 2
        ? ((c->stored+3)/4)*4 + ((c->regs+7)/4)*4-3
        : c->stored;
      CHECK(actual == c->actual);
      CHECK(c->ofd == (actual > 20));
      words = (actual+___WORD_WIDTH-1)/___WORD_WIDTH;
      table[0] = ___DEF_OFD(c->kind,c->stored,c->link);
      for (j=0; j<words; j++)
        {
#if ___WORD_WIDTH == 64
          table[j+1] = ___CAST(___WORD,
            ___CAST(___UWORD,c->chunks[2*j]) |
            (___CAST(___UWORD,c->chunks[2*j+1]) << 32));
#else
          table[j+1] = ___CAST(___WORD,c->chunks[j]);
#endif
        }
      encoded = c->ofd ? ___CAST(___WORD,table)
        : ___IFD(c->kind,c->stored,c->link,c->chunks[0]);
      frame = ___decode_frame_descriptor(encoded,c->kind == 2);
      {
        ___frame_descriptor checked_frame;
        CHECK(!___frame_is_unresolved_ofd(encoded));
        CHECK(___decode_frame_descriptor_checked(encoded,c->kind == 2,&checked_frame));
        CHECK(checked_frame.kind == frame.kind);
        CHECK(checked_frame.stored_fs == frame.stored_fs);
        CHECK(checked_frame.fs == frame.fs);
        CHECK(checked_frame.link == frame.link);
        CHECK(checked_frame.gcmap == frame.gcmap);
        CHECK(checked_frame.nextgcmap == frame.nextgcmap);
        if (c->kind != 2)
          CHECK(!___decode_frame_descriptor_checked(encoded,1,&checked_frame));
        {
          /* Exercise unified heap-frame descriptor & slot bijection contract. */
          ___label_struct lbl_box;
          ___SCMOBJ lbl_obj;
          ___WORD body[144];
          ___SCMOBJ fake_internal_ret = ___FIX(12345);
          ___frame_descriptor heap_frame;
          int s;
          lbl_box.header = ___MAKE_HD(0,___sRETURN,___PERM);
          lbl_box.entry_or_descr = encoded;
          lbl_obj = ___TAG(___CAST(___WORD*,&lbl_box.entry_or_descr) - ___REFERENCE_TO_BODY,
                           ___tSUBTYPED);
          if (c->kind == 2)
            {
              body[0] = fake_internal_ret;
              body[___FRAME_RETI_RA] = lbl_obj;
            }
          else
            body[0] = lbl_obj;
          CHECK(___decode_heap_frame_descriptor(body,fake_internal_ret,&heap_frame));
          CHECK(heap_frame.kind == frame.kind);
          CHECK(heap_frame.stored_fs == frame.stored_fs);
          CHECK(heap_frame.fs == frame.fs);
          CHECK(heap_frame.link == frame.link);
          CHECK(heap_frame.gcmap == frame.gcmap);
          CHECK(heap_frame.nextgcmap == frame.nextgcmap);
          for (s=1; s<=actual; s++)
            CHECK(___frame_heap_slot_ptr(body,&heap_frame,s) == body + (actual - s + 1));
          CHECK(___frame_heap_link_ptr(body,&heap_frame) ==
                ___frame_heap_slot_ptr(body,&heap_frame,c->link + 1));
        }
      }
      CHECK(frame.kind == c->kind);
      CHECK(frame.stored_fs == c->stored);
      CHECK(frame.fs == actual);
      CHECK(frame.link == c->link);
      CHECK(frame.nextgcmap == (c->ofd ? table+2 : 0));
      for (j=0; j<actual; j++)
        {
          ___UWORD bits = ___CAST(___UWORD,
            j < ___WORD_WIDTH ? frame.gcmap
                              : frame.nextgcmap[j/___WORD_WIDTH-1]);
          int bit = (int)((bits >> (j%___WORD_WIDTH)) & 1);
          int expected = c->pattern == 2 ||
            (c->pattern == 1 && (j == 0 || j == actual-1));
          CHECK(bit == expected);
          CHECK(___frame_slot_live (&frame, j+1) == expected);
        }
      {
        ___frame_root_cursor cursor = ___frame_root_begin (&frame);
        int covered[256] = {0};
        int first, past, previous = 0;
        CHECK(actual < 256);
        CHECK(!___frame_slot_live (&frame, -1));
        CHECK(!___frame_slot_live (&frame, 0));
        CHECK(!___frame_slot_live (&frame, actual+1));
        while (___frame_root_next_run (&cursor, &first, &past))
          {
            CHECK(first > previous && first < past && past <= actual+1);
            for (j=first; j<past; j++) covered[j]++;
            previous = past;
          }
        CHECK(!___frame_root_next_run (&cursor, &first, &past));
        for (j=1; j<=actual; j++)
          {
            int expected = c->pattern == 2 ||
              (c->pattern == 1 && (j == 1 || j == actual));
            CHECK(covered[j] == expected);
          }
        /* Ordinary roots and the structural link form a disjoint partition,
         * including live sign-bit and out-of-line map positions. */
        cursor = ___frame_ordinary_root_begin(&frame);
        for (j=0; j<256; j++) covered[j]=0;
        while (___frame_root_next_run(&cursor,&first,&past))
          for (j=first; j<past; j++) covered[j]++;
        for (j=1; j<=actual; j++)
          {
            int expected = (c->pattern == 2 ||
              (c->pattern == 1 && (j == 1 || j == actual))) &&
              j != c->link+1;
            CHECK(covered[j] == expected);
          }
      }
      /* Size-only consumers use the same decoded contract. */
      frame = ___decode_frame_descriptor(encoded,0);
      CHECK(frame.fs == c->stored);
      {
        int size_out, link_out;
        int internal_size = ((c->stored+3)/4)*4 + ((c->regs+7)/4)*4-3;
        ___WORD map_out;
        ___WORD *tail_out;
        unsigned int before = reads;
        ___RETI_GET_CFS(read_once(encoded),size_out)
        CHECK(size_out == c->stored);
        ___RETI_GET_FS(read_once(encoded),size_out)
        CHECK(size_out == internal_size);
        ___RETN_GET_FS(read_once(encoded),size_out)
        CHECK(size_out == c->stored);
        ___RETI_GET_FS_LINK(read_once(encoded),size_out,link_out)
        CHECK(size_out == internal_size && link_out == c->link);
        ___RETN_GET_FS_LINK(read_once(encoded),size_out,link_out)
        CHECK(size_out == c->stored && link_out == c->link);
        ___RETI_GET_FS_LINK_GCMAP(read_once(encoded),size_out,link_out,map_out,tail_out)
        CHECK(size_out == internal_size && link_out == c->link);
        CHECK(map_out == frame.gcmap && tail_out == frame.nextgcmap);
        ___RETN_GET_FS_LINK_GCMAP(read_once(encoded),size_out,link_out,map_out,tail_out)
        CHECK(size_out == c->stored && link_out == c->link);
        CHECK(map_out == frame.gcmap && tail_out == frame.nextgcmap);
        CHECK(reads == before+7);
      }
      checked++;
    }
  if (!checked) return 2;
  /* Adversarial FrameSpec authority checks: unresolved OFD placeholders,
   * invalid/misaligned OFD pointers, forged bounds, and zero-map inline IFDs. */
  {
    ___frame_descriptor bad;
    ___WORD forged_zero[2];
    ___WORD forged_link[2];
    ___WORD valid_zero_map = ___IFD(___RETN,8,7,0);
    i = 0;
    CHECK(___frame_is_unresolved_ofd(___OFD(___RETN,0,0,0)));
    CHECK(___frame_is_unresolved_ofd(___OFD(___RETI,0,0,0)));
    CHECK(___frame_is_unresolved_ofd(___OFD(___RETT,0,0,0)));
    CHECK(!___frame_is_unresolved_ofd(valid_zero_map));
    CHECK(!___decode_frame_descriptor_checked(___OFD(___RETN,0,0,0),0,&bad));
    CHECK(!___decode_frame_descriptor_checked(___OFD(___RETI,0,0,0),1,&bad));
    CHECK(!___decode_frame_descriptor_checked(___OFD(___RETT,0,0,0),0,&bad));
    CHECK(!___decode_frame_descriptor_checked(0,0,&bad));
    CHECK(!___decode_frame_descriptor_checked(___CAST(___WORD,0x100),0,&bad));
#if ___WS >= 8
    /* Low 2 bits == 0 classifies as OFD, but +4 violates 8-byte word alignment. */
    CHECK(!___decode_frame_descriptor_checked(___CAST(___WORD,forged_zero) + 4,0,&bad));
#endif
    forged_zero[0] = ___DEF_OFD(___RETN,0,0);
    forged_zero[1] = 0;
    CHECK(!___decode_frame_descriptor_checked(___CAST(___WORD,forged_zero),0,&bad));
    forged_link[0] = ___DEF_OFD(___RETN,4,4);
    forged_link[1] = 0;
    CHECK(!___decode_frame_descriptor_checked(___CAST(___WORD,forged_link),0,&bad));
    CHECK(___decode_frame_descriptor_checked(valid_zero_map,0,&bad));
    CHECK(bad.kind == ___RETN && bad.fs == 8 && bad.link == 7 && bad.gcmap == 0);
    CHECK(!___decode_frame_descriptor_checked(valid_zero_map,1,&bad));
  }
  printf("FRAME-CONTRACT-PASS regs=%d cases=%u word=%d\n",
         ___NB_GVM_REGS,checked,___WORD_WIDTH);
  return 0;
}
