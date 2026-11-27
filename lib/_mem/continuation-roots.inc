#line 4085 ___MEM_SOURCE_FILE
/* Resolve the old half and stack claim before loading any frame word. The
 * descriptor itself is trusted live module metadata, as in the ordinary
 * frame decoder. A captured suffix may have no independent logical end. */
___HIDDEN ___msection *resolve_source_half(___msections *sections,
                                           ___WORD *top,
                                           ___SIZE_TS source_offset,
                                           ___SIZE_TS *half_words)
{
  ___msection *section;
  ___UWORD address=___CAST(___UWORD,top),first,half_past;
  int i;
  if (!sections || (source_offset!=0 && source_offset!=(___MSECTION_SIZE>>1))) return 0;
  i=find_msection(sections,top);
  if (i<0 || i>=sections->nb_sections) return 0;
  section=sections->sections[i];
  first=___CAST(___UWORD,section->base+source_offset);
  half_past=first+___CAST(___UWORD,___MSECTION_SIZE>>1)*___WS;
  if ((first%___WS)!=0 || (address%___WS)!=0 || address<first || address>=half_past)
    return 0;
  *half_words=(half_past-address)/___WS;
  return section;
}

___HIDDEN ___BOOL source_claim_is_live(const section_claim *claim)
{
  return claim->stack_owner &&
    (claim->stack_state==STACK_ACTIVE || claim->stack_state==STACK_PARKED);
}

___HIDDEN ___msection *admit_source_stack_span(___collector_worker *work,
                                              ___WORD *top,
                                              ___SIZE_TS source_offset,
                                              ___WORD *logical_past,
                                              ___SIZE_TS *half_words)
{
  ___processor_state ___ps=work->carrier;
  ___msection *section;
  ___UWORD address=___CAST(___UWORD,top), first, half_past;
  if (source_offset!=0 && source_offset!=(___MSECTION_SIZE>>1)) return 0;
  section=___gc_find_msection_cached(work, the_msections, top);
  if (!section) return 0;
  first=___CAST(___UWORD,section->base+source_offset);
  half_past=first+___CAST(___UWORD,___MSECTION_SIZE>>1)*___WS;
  if ((first%___WS)!=0 || (address%___WS)!=0 || address<first || address>=half_past)
    return 0;
  *half_words=(half_past-address)/___WS;
  if (!source_claim_is_live(section_claim_at(section,source_offset))) return 0;
  if (logical_past) {
    ___UWORD logical=___CAST(___UWORD,logical_past);
    if ((logical%___WS)!=0 || logical<address || (logical-address)/___WS>*half_words) return 0;
  }
  return section;
}

___HIDDEN int decode_source_stack_frame(___WORD *top, ___SIZE_TS remaining,
                                       ___WORD *ra, int carry,
                                       ___frame_descriptor *frame)
{
  int internal;
  ___WORD label;
  if (!remaining || !top || !ra || !frame) return 0;
  if (!carry) *ra=___FP_STK(top,-___FRAME_STACK_RA);
  internal=*ra==___GSTATE->internal_return;
  if (internal && ___CAST(___SIZE_TS,-___RETI_RA)>=remaining) return 0;
  label=internal ? ___FP_STK(top,___RETI_RA) : *ra;
  /* Only a permanent return label object has a frame descriptor. A fixnum
   * or non-return subtyped object (such as a heap frame/continuation at a
   * chain boundary) is not a code label, and decoding it faults. */
  if (___TYP(label)!=___tSUBTYPED) return 0;
  {
    ___WORD *body=___UNTAG(label);
    ___WORD hd, descr;
    if (!body || (___CAST(___UWORD,body)&(___WS-1)) ||
        ___CAST(___UWORD,body)<0x10000) return 0;
    hd=___SUBTYPED_HEADER(label);
    if (___HD_SUBTYPE(hd)!=___sRETURN || ___HD_TYP(hd)!=___PERM) return 0;
    descr=___LABEL_DESCR_GET(label);
    if (!___decode_frame_descriptor_checked(descr, internal, frame)) return 0;
  }
  if (___CAST(___SIZE_TS,___FRAME_SPACE(frame->fs))>remaining) return 0;
  return 1;
}

/* Find the nearest marks in the owning half before reading any payload.
 * Between an END and the next START is a break or a capture-object gap. */
___HIDDEN ___WORD *raw_stack_span_end(const section_claim *claim, ___WORD *base,
                                     ___WORD *top)
{
  ___SIZE_TS index=top-base;
  ___SIZE_TS low=claim->raw_low-base, high=claim->raw_high-base;
  const unsigned char *marks=claim->raw_marks;
  ___SIZE_TS prev=index, next=index+1;

#if defined(__GNUC__) && defined(__BYTE_ORDER__) && (__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__) && !defined(CBMC)
  {
    const ___SIZE_TS max_wi = (___SIZE_TS)(RAW_STACK_MAP_BYTES / 8);
    ___SIZE_TS wi = prev >> 5;
    ___SIZE_TS lo_wi = low >> 5;
    if (wi < max_wi) {
      unsigned int top_bit = (unsigned int)((prev & 31) * 2 + 1);
      ___U64 hi_mask = (top_bit == 63) ? ~(___U64)0 : (((___U64)1 << (top_bit + 1)) - 1);
      ___SIZE_TS found = low;
      for (;;) {
        ___U64 w;
        memcpy(&w, &marks[wi * 8], 8);
        w &= hi_mask;
        hi_mask = ~(___U64)0;
        if (wi == lo_wi) {
          unsigned int lo_bit = (unsigned int)((low & 31) * 2);
          w &= (~(___U64)0) << lo_bit;
        }
        if (w != 0) {
          unsigned int hb = 63U - (unsigned int)__builtin_clzll(w);
          found = (wi << 5) + (___SIZE_TS)(hb >> 1);
          break;
        }
        if (wi <= lo_wi) break;
        wi--;
      }
      prev = found;
    } else {
      while (prev>low && !raw_stack_mark_at(marks,prev)) prev--;
    }
    if (raw_stack_mark_at(marks,prev)!=RAW_STACK_START) return 0;

    if (next < high) {
      ___SIZE_TS nwi = next >> 5;
      ___SIZE_TS hi_wi = high >> 5;
      if (hi_wi < max_wi) {
        unsigned int lo_bit = (unsigned int)((next & 31) * 2);
        ___U64 lo_mask = (~(___U64)0) << lo_bit;
        ___SIZE_TS found = high;
        for (;;) {
          ___U64 w;
          memcpy(&w, &marks[nwi * 8], 8);
          w &= lo_mask;
          lo_mask = ~(___U64)0;
          if (nwi == hi_wi) {
            unsigned int hb = (unsigned int)((high & 31) * 2 + 1);
            w &= (hb == 63) ? ~(___U64)0 : (((___U64)1 << (hb + 1)) - 1);
          }
          if (w != 0) {
            unsigned int lb = (unsigned int)__builtin_ctzll(w);
            found = (nwi << 5) + (___SIZE_TS)(lb >> 1);
            break;
          }
          if (nwi >= hi_wi) break;
          nwi++;
        }
        next = found;
      } else {
        while (next<high && !raw_stack_mark_at(marks,next)) next++;
      }
    }
  }
#else
  while (prev>low && !raw_stack_mark_at(marks,prev)) {
    if ((prev&31)==31 && prev-low>=32) {
      ___U64 z;
      memcpy(&z, &marks[(prev-31)>>2], 8);
      if (z==0) { prev-=32; continue; }
    }
    prev-=prev%4==3 && !marks[prev/4] && prev-low>=4 ? 4 : 1;
  }
  if (raw_stack_mark_at(marks,prev)!=RAW_STACK_START) return 0;

  while (next<high && !raw_stack_mark_at(marks,next)) {
    if ((next&31)==0 && high-next>=32) {
      ___U64 z;
      memcpy(&z, &marks[next>>2], 8);
      if (z==0) { next+=32; continue; }
    }
    next+=next%4==0 && !marks[next/4] && high-next>=4 ? 4 : 1;
  }
#endif
  return raw_stack_mark_at(marks,next)==RAW_STACK_END ? base+next : 0;
}

___HIDDEN int read_admitted_stack_frame(const section_claim *claim,
                                        ___WORD *top, ___SIZE_TS half_words,
                                        ___WORD *logical_past,
                                        ___WORD *ra, int carry,
                                        ___frame_descriptor *frame,
                                        ___WORD **known_break_out)
{
  ___UWORD address=___CAST(___UWORD,top);
  if (!claim || !top || (address & (___WS-1))) return 0;
  if (!logical_past && claim->stack_state==STACK_PARKED && claim->parked_top &&
      address>=___CAST(___UWORD,claim->parked_top) &&
      address<=___CAST(___UWORD,claim->parked_break))
    logical_past=claim->parked_break;
  if (!logical_past && claim->raw_marks &&
      address>=___CAST(___UWORD,claim->raw_low) &&
      address<=___CAST(___UWORD,claim->raw_high))
    {
      ___WORD *base=top-((___MSECTION_SIZE>>1)-half_words);
      logical_past=raw_stack_span_end(claim,base,top);
      if (!logical_past) return 0;
    }
  if (!decode_source_stack_frame(top,logical_past ? logical_past-top : half_words,
                                 ra,carry,frame)) return 0;
  if (known_break_out) *known_break_out=logical_past;
  return 1;
}

___HIDDEN ___msection *read_source_stack_frame(___collector_worker *work,
                                              ___WORD *top,
                                              ___SIZE_TS source_offset,
                                              ___WORD *logical_past,
                                              ___WORD *ra, int carry,
                                              ___frame_descriptor *frame,
                                              ___SIZE_TS *half_words_out,
                                              ___WORD **known_break_out)
{
  ___SIZE_TS half_words;
  ___msection *section=admit_source_stack_span(work,top,source_offset,
                                               logical_past,&half_words);
  if (!section || !read_admitted_stack_frame(section_claim_at(section,source_offset),
        top,half_words,logical_past,ra,carry,frame,known_break_out)) return 0;
  if (half_words_out) *half_words_out=half_words;
  return section;
}

/* Once the producer supplies a logical end, an ordinary successor cannot
 * cross it. A copied suffix can already terminate via a forwarding link. */
___HIDDEN int source_break_agrees(___WORD *base, ___WORD *known_break, ___WORD link)
{
  if (___FIXNUMP(link)) return link!=___END_OF_CONT_MARKER;
  return !known_break || ((base==known_break)==(link==___GSTATE->handler_break));
}

/* Raw break links can be installed by a different carrier. The existing
 * raw-continuation publication keeps their frames resident. Resolve the
 * shared map under its allocation lock and keep the source section gate
 * across claim inspection, descriptor reads and link updates. Collection
 * cannot retire a half while this nonpolling mutator is running. */
___HIDDEN ___msection *lock_source_stack_frame
 (___processor_state ___ps, ___WORD *top, ___SIZE_TS *half_words,
  ___WORD *ra, ___frame_descriptor *frame, ___WORD **known_break)
{
  ___msection *section = 0;
  const section_claim *claim;
  ___UWORD address = ___CAST(___UWORD,top);
  ___SIZE_TS off = tospace_offset;
  ___UWORD half_bytes = ___CAST(___UWORD,___MSECTION_SIZE>>1)*___WS;
  ___UWORD cur_epoch = ___COLLECTION(___VMSTATE_FROM_PSTATE(___ps)).epoch;

  if (top && (address & (___WS-1)) == 0 && (off == 0 || off == (___MSECTION_SIZE>>1)))
    {
      /* Fast path 1: carrier's own active stack_msection (cannot be freed
       * while this nonpolling mutator is executing). */
      ___msection *own = stack_msection;
      if (own)
        {
          ___UWORD first = ___CAST(___UWORD,own->base + off);
          if ((first & (___WS-1)) == 0 && address >= first && address - first < half_bytes)
            {
              section = own;
              *half_words = (half_bytes - (address - first)) / ___WS;
              ___gc_copy_acquire(&section->copy_gate);
            }
        }

      /* Fast path 2: processor-private epoch-validated section cache.
       * adjust_msections never shrinks or frees sections outside STW GC,
       * and STW GC increments epoch while all mutators are stopped. */
      if (!section && ___ps->mem.src_stack_cache_epoch_ == cur_epoch &&
          ___ps->mem.src_stack_cache_offset_ == off)
        {
          int ci;
          for (ci = 0; ci < 4; ci++)
            {
              ___msection *cand = ___ps->mem.src_stack_cache_sec_[ci];
              if (cand)
                {
                  ___UWORD first = ___ps->mem.src_stack_cache_base_[ci];
                  if (address >= first && address - first < half_bytes)
                    {
                      section = cand;
                      *half_words = (half_bytes - (address - first)) / ___WS;
                      ___gc_copy_acquire(&section->copy_gate);
                      break;
                    }
                }
            }
        }
    }

  if (!section)
    {
      ALLOC_MEM_LOCK();
      section=resolve_source_half(the_msections,top,off,half_words);
      if (section) ___gc_copy_acquire(&section->copy_gate);
      ALLOC_MEM_UNLOCK();
      if (!section) return 0;

      if (___ps->mem.src_stack_cache_epoch_ != cur_epoch ||
          ___ps->mem.src_stack_cache_offset_ != off)
        {
          ___ps->mem.src_stack_cache_sec_[0] = 0;
          ___ps->mem.src_stack_cache_sec_[1] = 0;
          ___ps->mem.src_stack_cache_sec_[2] = 0;
          ___ps->mem.src_stack_cache_sec_[3] = 0;
          ___ps->mem.src_stack_cache_epoch_ = cur_epoch;
          ___ps->mem.src_stack_cache_offset_ = off;
          ___ps->mem.src_stack_cache_next_ = 0;
        }
      if (section != stack_msection)
        {
          int slot = ___ps->mem.src_stack_cache_next_ & 3;
          ___ps->mem.src_stack_cache_sec_[slot] = section;
          ___ps->mem.src_stack_cache_base_[slot] = ___CAST(___UWORD,section->base + off);
          ___ps->mem.src_stack_cache_next_ = (slot + 1) & 3;
        }
    }

  claim=section_claim_at(section,off);
  if (!source_claim_is_live(claim) ||
      !read_admitted_stack_frame(claim,top,*half_words,0,ra,0,frame,known_break))
    {
      ___gc_copy_release(&section->copy_gate);
      return 0;
    }
  return section;
}

/* Chez PLDI '90 bounded multi-frame chunk restore (underflow_limit = 512 words / 4 KiB):
 * Restores up to 64 contiguous frames (<= 512 words) in ONE copy_gate critical section
 * and ONE contiguous memcpy, eliminating per-frame handler_break bounces while preserving
 * ZGC Stack Watermark x SATB shading across every restored frame in the chunk. */
___WORD ___restore_stack_break_frame(___processor_state ___ps, ___WORD *top,
                                     ___WORD **stack_cursor)
{
  enum { CHUNK_MAX_WORDS = 512, CHUNK_MAX_FRAMES = 64 };
  ___SIZE_TS half_words, words, total_words, dest_room = 0;
  ___msection *section;
  ___WORD *known_break, *base, *last_base, *dest=*stack_cursor;
  ___WORD *dest_lo = 0, *dest_hi = 0;
  ___WORD ra, next, last_next;
  ___frame_descriptor fds[CHUNK_MAX_FRAMES];
  ___SIZE_TS fwords[CHUNK_MAX_FRAMES];
  int nframes = 0;

  /* Query active destination stack room BEFORE acquiring section->copy_gate
   * (___owned_stack_span may acquire stack_msection->copy_gate).
   * Reserve ___MSECTION_FUDGE above dest_lo so multi-frame chunking never
   * pushes ___fp into the stack guard/fudge zone (which would trip
   * ___handler_spill_backed -> stack-overflow-exception). */
  if (___owned_stack_span(___ps, &dest_lo, &dest_hi) &&
      dest >= dest_lo && dest <= dest_hi)
    {
      ___WORD *safe_lo = dest_lo + ___MSECTION_FUDGE;
      if (dest > safe_lo)
        dest_room = ___CAST(___SIZE_TS, dest - safe_lo);
    }

  section=lock_source_stack_frame(___ps,top,&half_words,&ra,&fds[0],&known_break);
  if (!section) goto refused;
  words=___FRAME_SPACE(fds[0].fs);
  base=top+words;
  next=___FP_STK(base,fds[0].link+1);
  if (___FIXNUMP(next) || !source_break_agrees(base,known_break,next) ||
      half_words-words <= (next==___GSTATE->handler_break ? ___BREAK_FRAME_NEXT : 0))
    goto release_and_refuse;

  if (ra==___GSTATE->internal_return) {
    ___COVER_BREAK_HANDLER_STACK_RETI;
  } else {
    ___COVER_BREAK_HANDLER_STACK_RETN;
  }

  fwords[0] = words;
  nframes = 1;
  total_words = words;
  last_base = base;
  last_next = next;

  /* Extend chunk up to CHUNK_MAX_WORDS (4 KiB) while contiguous frames fit both
   * source grant and active destination stack span. */
  while (nframes < CHUNK_MAX_FRAMES &&
         last_next != ___GSTATE->handler_break &&
         !___FIXNUMP(last_next))
    {
      ___SIZE_TS rem = known_break ? ___CAST(___SIZE_TS, known_break - last_base)
                                   : (half_words - total_words);
      ___WORD cand_ra = last_next;
      ___frame_descriptor cand_fd;
      ___SIZE_TS cand_words;
      ___WORD *cand_base;
      ___WORD cand_next;

      if (rem == 0 ||
          !decode_source_stack_frame(last_base, rem, &cand_ra, 1, &cand_fd))
        break;
      cand_words = ___FRAME_SPACE(cand_fd.fs);
      if (total_words + cand_words > CHUNK_MAX_WORDS ||
          total_words + cand_words > half_words ||
          total_words + cand_words > dest_room)
        break;
      cand_base = last_base + cand_words;
      cand_next = ___FP_STK(cand_base, cand_fd.link + 1);
      if (___FIXNUMP(cand_next) ||
          !source_break_agrees(cand_base, known_break, cand_next) ||
          half_words - (total_words + cand_words) <=
            (cand_next == ___GSTATE->handler_break ? ___BREAK_FRAME_NEXT : 0))
        break;

      fds[nframes] = cand_fd;
      fwords[nframes] = cand_words;
      nframes++;
      total_words += cand_words;
      last_base = cand_base;
      last_next = cand_next;
    }

  /* Copy the entire contiguous [top .. last_base) chunk to [dest - total_words .. dest). */
  if (nframes == 1)
    {
      int i;
      for (i = fds[0].fs; i > 0; i--)
        ___FP_SET_STK(dest, i, ___FP_STK(base, i))
    }
  else
    {
      memcpy(dest - total_words, top, total_words * sizeof(___WORD));
    }

  if (last_next == ___GSTATE->handler_break)
    {
      ___COVER_BREAK_HANDLER_STACK_FIRST_FRAME;
      ___FP_SET_STK(dest, -___BREAK_FRAME_NEXT, ___FP_STK(last_base, -___BREAK_FRAME_NEXT))
    }
  else
    {
      ___COVER_BREAK_HANDLER_STACK_NOT_FIRST_FRAME;
      ___FP_SET_STK(last_base, -___FRAME_STACK_RA, last_next)
      ___FP_SET_STK(dest, -___BREAK_FRAME_NEXT, ___CAST(___WORD, last_base))
      ___FP_SET_STK(dest, fds[nframes - 1].link + 1, ___GSTATE->handler_break)
    }

  *stack_cursor = dest - total_words;
  ___gc_copy_release(&section->copy_gate);

  /* ZGC Stack Watermark x SATB: shade ALL nframes restored frames in the chunk! */
  if (___EXPECT_FALSE(___ps->mem.satb_active_ != 0))
    {
      ___WORD *fbase = dest - total_words;
      int fi;
      for (fi = 0; fi < nframes; fi++)
        {
          ___frame_root_cursor cursor = ___frame_ordinary_root_begin(&fds[fi]);
          int first, past;
          fbase += fwords[fi];
          while (___frame_root_next_run(&cursor, &first, &past))
            ___gc_satb_barrier_range(___ps, &___FP_STK(fbase, past - 1),
                                     ___CAST(___SIZE_TS, past - first));
        }
      ___WORD_STORE_RELAXED(&___ps->mem.stack_watermark_shaded_frames_,
                            ___ps->mem.stack_watermark_shaded_frames_ + nframes);
    }
  return ra;

 release_and_refuse:
  ___gc_copy_release(&section->copy_gate);
 refused:
  rc_contract_error("Break restore source frame is outside its stack grant");
  return ___FAL;
}

/* Reclaim and rewind a one-shot prompt escape continuation in-place when
 * returning through %mc-return1 (eliminates worker-loop stack_break ratcheting). */
int ___try_rewind_prompt_span(___processor_state ___ps,
                              ___SCMOBJ escape_k,
                              ___WORD *ra_out,
                              ___WORD **new_fp_out)
{
  ___msection *section = stack_msection;
  section_claim *claim;
  ___WORD *base, *top, *brk, *span_end;
  ___SCMOBJ raw, cur_denv, esc_denv;
  ___SIZE_TS capture_delta, half_words;

  if (!section || !___TESTTYPE(escape_k, ___tCONTINUATION))
    return 0;

  /* NEVER reclaim a stack-allocated continuation in-place while concurrent
   * SATB major GC is active: the SATB write barrier or a concurrent marker
   * thread may still hold a pointer to escape_k in the rewound stack span. */
  if (___EXPECT_FALSE(___ps->mem.satb_active_ != 0))
    return 0;

  cur_denv = ___THREAD_DENV_FIELD(___CURRENTTHREAD);
  esc_denv = ___CONTINUATION_DENV_FIELD(escape_k);
  if (cur_denv != esc_denv)
    return 0;

  raw = ___CONTINUATION_FRAME_FIELD(escape_k);
  if (raw == ___END_OF_CONT_MARKER || !___FIXNUMP(raw))
    return 0;
  top = ___CAST(___WORD*, raw);
  brk = ___ps->context->stack_break;
  capture_delta =
    ___ROUND_TO_MULT(___SUBTYPED_BODY + ___CONTINUATION_SIZE, ___FRAME_ALIGN) +
    ___BREAK_FRAME_SPACE;
  if (top - capture_delta != brk)
    return 0;

  if (tospace_offset != 0 && tospace_offset != (___MSECTION_SIZE >> 1))
    return 0;
  base = start_of_tospace(section);
  half_words = ___MSECTION_SIZE >> 1;
  if (top < base || top >= base + half_words)
    return 0;

  claim = section_claim_at(section, tospace_offset);
  ___gc_copy_acquire(&section->copy_gate);
  if (claim->stack_owner != ___ps || claim->stack_state != STACK_ACTIVE ||
      !claim->raw_marks || claim->raw_low != top)
    {
      ___gc_copy_release(&section->copy_gate);
      return 0;
    }

  span_end = raw_stack_span_end(claim, base, top);
  if (!span_end || span_end <= top || span_end > base + half_words)
    {
      ___gc_copy_release(&section->copy_gate);
      return 0;
    }

  raw_stack_clear_mark(claim->raw_marks, top - base);
  raw_stack_clear_mark(claim->raw_marks, span_end - base);
  if (span_end >= claim->raw_high)
    {
      claim->raw_marks = 0;
      claim->raw_low = 0;
      claim->raw_high = 0;
    }
  else
    {
      ___SIZE_TS idx = (span_end - base) + 1;
      ___SIZE_TS hi = claim->raw_high - base;
      while (idx < hi && raw_stack_mark_at(claim->raw_marks, idx) != RAW_STACK_START)
        idx++;
      if (idx < hi)
        claim->raw_low = base + idx;
      else
        {
          claim->raw_marks = 0;
          claim->raw_low = 0;
          claim->raw_high = 0;
        }
    }
  ___gc_copy_release(&section->copy_gate);

  if (___EXPECT_FALSE(___ps->mem.satb_active_ != 0))
    {
      ___WORD tmp_ra;
      ___frame_descriptor fd;
      if (decode_source_stack_frame(top, span_end - top, &tmp_ra, 0, &fd))
        {
          ___WORD *fbase = top + ___FRAME_SPACE(fd.fs);
          ___frame_root_cursor cursor = ___frame_ordinary_root_begin(&fd);
          int first, past;
          while (___frame_root_next_run(&cursor, &first, &past))
            ___gc_satb_barrier_range(___ps, &___FP_STK(fbase, past - 1),
                                     ___CAST(___SIZE_TS, past - first));
          ___WORD_STORE_RELAXED(&___ps->mem.stack_watermark_shaded_frames_,
                                ___ps->mem.stack_watermark_shaded_frames_ + 1);
        }
    }

  ___ps->context->stack_break = span_end;
  *new_fp_out = top;
  *ra_out = ___FP_STK(top, -___FRAME_STACK_RA);
  ___WORD_STORE_RELAXED(&___ps->mem.oneshot_rewinds_local_,
                        ___ps->mem.oneshot_rewinds_local_ + 1);
  return 1;
}

/* Reclaim and rewind a linearly-claimed one-shot continuation in-place when
 * its captured span sits directly above stack_break on this processor's active
 * stack section and the handler tail-resumed directly on escape_k. Eliminates
 * monotonic stack_break ratcheting, break-frame copying, and dead-frame GC
 * pressure while preserving ZGC stack watermark SATB invariants. */
int ___try_rewind_oneshot_span(___processor_state ___ps,
                               ___SCMOBJ sub_k,
                               ___SCMOBJ escape_k,
                               ___WORD *cur_fp,
                               ___WORD cur_r0,
                               ___WORD *ra_out,
                               ___WORD **new_fp_out)
{
  ___msection *section = stack_msection;
  section_claim *claim;
  ___WORD *base, *top, *brk, *span_end;
  ___SCMOBJ raw, esc_frame, cur_denv, sub_denv;
  ___SIZE_TS capture_delta, half_words;

  if (!section || !___TESTTYPE(sub_k, ___tCONTINUATION) ||
      !___TESTTYPE(escape_k, ___tCONTINUATION))
    return 0;

  /* NEVER reclaim a stack-allocated continuation in-place while concurrent
   * SATB major GC is active: the SATB write barrier (from clearing ek->sub_k)
   * or a concurrent marker thread may still scan sub_k in the rewound span. */
  if (___EXPECT_FALSE(___ps->mem.satb_active_ != 0))
    return 0;

  brk = ___ps->context->stack_break;
  if (cur_fp != brk || cur_r0 != ___ps->handler_break)
    return 0;

  esc_frame = ___CONTINUATION_FRAME_FIELD(escape_k);
  if (___FP_STK(cur_fp, -___BREAK_FRAME_NEXT) != esc_frame)
    return 0;

  /* Require identical dynamic environment so dynamic-wind / parameterize
   * transitions always take the general winding path. */
  cur_denv = ___THREAD_DENV_FIELD(___CURRENTTHREAD);
  sub_denv = ___CONTINUATION_DENV_FIELD(sub_k);
  if (cur_denv != sub_denv)
    return 0;

  raw = ___CONTINUATION_FRAME_FIELD(sub_k);
  if (raw == ___END_OF_CONT_MARKER || !___FIXNUMP(raw))
    return 0;
  top = ___CAST(___WORD*, raw);
  capture_delta =
    ___ROUND_TO_MULT(___SUBTYPED_BODY + ___CONTINUATION_SIZE, ___FRAME_ALIGN) +
    ___BREAK_FRAME_SPACE;
  if (top - capture_delta != brk)
    return 0;

  if (tospace_offset != 0 && tospace_offset != (___MSECTION_SIZE >> 1))
    return 0;
  base = start_of_tospace(section);
  half_words = ___MSECTION_SIZE >> 1;
  if (top < base || top >= base + half_words)
    return 0;

  claim = section_claim_at(section, tospace_offset);
  ___gc_copy_acquire(&section->copy_gate);
  if (claim->stack_owner != ___ps || claim->stack_state != STACK_ACTIVE ||
      !claim->raw_marks || claim->raw_low != top)
    {
      ___gc_copy_release(&section->copy_gate);
      return 0;
    }

  span_end = raw_stack_span_end(claim, base, top);
  if (!span_end || span_end <= top || span_end > base + half_words)
    {
      ___gc_copy_release(&section->copy_gate);
      return 0;
    }

  raw_stack_clear_mark(claim->raw_marks, top - base);
  raw_stack_clear_mark(claim->raw_marks, span_end - base);
  if (span_end >= claim->raw_high)
    {
      claim->raw_marks = 0;
      claim->raw_low = 0;
      claim->raw_high = 0;
    }
  else
    {
      ___SIZE_TS idx = (span_end - base) + 1;
      ___SIZE_TS hi = claim->raw_high - base;
      while (idx < hi && raw_stack_mark_at(claim->raw_marks, idx) != RAW_STACK_START)
        idx++;
      if (idx < hi)
        claim->raw_low = base + idx;
      else
        {
          claim->raw_marks = 0;
          claim->raw_low = 0;
          claim->raw_high = 0;
        }
    }
  ___gc_copy_release(&section->copy_gate);

  if (___EXPECT_FALSE(___ps->mem.satb_active_ != 0))
    {
      ___WORD tmp_ra;
      ___frame_descriptor fd;
      if (decode_source_stack_frame(top, span_end - top, &tmp_ra, 0, &fd))
        {
          ___WORD *fbase = top + ___FRAME_SPACE(fd.fs);
          ___frame_root_cursor cursor = ___frame_ordinary_root_begin(&fd);
          int first, past;
          while (___frame_root_next_run(&cursor, &first, &past))
            ___gc_satb_barrier_range(___ps, &___FP_STK(fbase, past - 1),
                                     ___CAST(___SIZE_TS, past - first));
          ___WORD_STORE_RELAXED(&___ps->mem.stack_watermark_shaded_frames_,
                                ___ps->mem.stack_watermark_shaded_frames_ + 1);
        }
    }

  ___ps->context->stack_break = span_end;
  *new_fp_out = top;
  *ra_out = ___FP_STK(top, -___FRAME_STACK_RA);
  ___WORD_STORE_RELAXED(&___ps->mem.oneshot_rewinds_local_,
                        ___ps->mem.oneshot_rewinds_local_ + 1);
  return 1;
}

/* Inspect or change one raw frame under the same gate as restore. A
 * debugger payload write must not alter the chain or saved descriptor. */
___SCMOBJ ___access_raw_continuation_frame
 (___processor_state ___ps, ___SCMOBJ raw, enum ___raw_frame_operation op,
  ___SCMOBJ index, ___SCMOBJ value)
{
  ___WORD *top, *base, *known_break, ra;
  ___SIZE_TS half_words, words;
  ___msection *section;
  ___frame_descriptor frame;
  ___SCMOBJ result;
  ___WORD slot=0;

  if (raw==___END_OF_CONT_MARKER || !___FIXNUMP(raw))
    {
      rc_contract_error("Reflective continuation cursor is not a raw stack frame");
      return ___FAL;
    }
  top=___CAST(___WORD*,raw);
  section=lock_source_stack_frame(___ps,top,&half_words,&ra,&frame,&known_break);
  if (!section)
    {
      rc_contract_error("Reflective continuation frame is outside its stack section");
      return ___FAL;
    }

  if (op==___RAW_FRAME_LIVE || op==___RAW_FRAME_REF || op==___RAW_FRAME_SET)
    {
      if (___FIXNUMP(index)) slot=___INT(index);
      if (slot<=0 || slot>frame.fs)
        {
          if (op!=___RAW_FRAME_LIVE) goto release_and_refuse;
          ___gc_copy_release(&section->copy_gate);
          return ___FAL;
        }
    }

  words=___FRAME_SPACE(frame.fs);
  base=top+words;
  switch (op)
    {
    case ___RAW_FRAME_RET:
      result=ra==___GSTATE->internal_return ? ___FP_STK(top,___RETI_RA) : ra;
      break;
    case ___RAW_FRAME_FS:
      result=___FIX(frame.fs);
      break;
    case ___RAW_FRAME_LINK:
      result=___FIX(frame.link+1);
      break;
    case ___RAW_FRAME_LIVE:
      result=___BOOLEAN(___frame_slot_live(&frame,slot));
      break;
    case ___RAW_FRAME_REF:
      result=___FP_STK(base,slot);
      break;
    case ___RAW_FRAME_SET:
      if (slot==frame.link+1 ||
          (ra==___GSTATE->internal_return && slot==words+___RETI_RA))
        goto release_and_refuse;
      ___FP_SET_STK(base,slot,value)
      result=___VOID;
      break;
    default:
      goto release_and_refuse;
    }
  ___gc_copy_release(&section->copy_gate);
  return result;

 release_and_refuse:
  ___gc_copy_release(&section->copy_gate);
 refused:
  rc_contract_error("Reflective continuation slot is outside its stack grant");
  return ___FAL;
}

/* The caller owns cont as a mutable cursor. Shared stack words are
 * serialized with other raw mutators by the same gate as break restore.
 * A raw NEXT at a break is copied as an edge, without reading its target. */
___WORD ___continuation_next_stack(___processor_state ___ps, ___SCMOBJ cont)
{
  enum { dynamic_env_slot = 2 };
  ___SCMOBJ raw=___CONTINUATION_FRAME_FIELD(cont);
  ___SCMOBJ denv, successor;
  ___WORD *top, *base, *known_break, ra, next;
  ___SIZE_TS half_words, words;
  ___msection *section;
  ___frame_descriptor frame;
  int at_break;

  if (raw==___END_OF_CONT_MARKER) return ___FAL;
  if (!___FIXNUMP(raw)) goto refused;
  top=___CAST(___WORD*,raw);
  section=lock_source_stack_frame(___ps,top,&half_words,&ra,&frame,&known_break);
  if (!section) goto refused;

  words=___FRAME_SPACE(frame.fs);
  base=top+words;
  next=___FP_STK(base,frame.link+1);
  at_break=next==___GSTATE->handler_break;
  if (___FIXNUMP(next) || !source_break_agrees(base,known_break,next) ||
      half_words-words <= (at_break ? ___BREAK_FRAME_NEXT : 0))
    goto release_and_refuse;

  denv=___CONTINUATION_DENV_FIELD(cont);
  if (ra==___ps->dynamic_env_bind_return)
    {
      if (frame.fs<dynamic_env_slot) goto release_and_refuse;
      denv=___FP_STK(base,dynamic_env_slot);
    }
  if (at_break)
    successor=___FP_STK(base,-___BREAK_FRAME_NEXT);
  else
    {
      ___FP_SET_STK(base,-___FRAME_STACK_RA,next)
      successor=___CAST(___SCMOBJ,base);
    }
  if (successor==___END_OF_CONT_MARKER)
    cont=___FAL;
  else
    {
      ___GC_WRITE_BARRIER_ALWAYS(___ps, cont, &___CONTINUATION_FRAME_FIELD(cont));
      ___GC_WRITE_BARRIER(___ps, cont, &___CONTINUATION_DENV_FIELD(cont), denv);
      ___WORD_STORE_RELAXED(&___CONTINUATION_FRAME_FIELD(cont), successor);
      ___WORD_STORE_RELAXED(&___CONTINUATION_DENV_FIELD(cont), denv);
    }
  ___gc_copy_release(&section->copy_gate);
  return cont;

 release_and_refuse:
  ___gc_copy_release(&section->copy_gate);
 refused:
  rc_contract_error("Reflective continuation source frame is outside its stack grant");
  return ___FAL;
}

/* Caller owns frame access across the initial read, source-frame forwarding,
 * root repairs and every destination-link update. No collector waits for
 * frame access while still holding a FIFO gate. */
___HIDDEN void mark_captured_continuation_locked
   ___P((___collector_worker *work,
         ___WORD *orig_ptr),
        (work,
         orig_ptr)
___collector_worker *work;
___WORD *orig_ptr;)
{
  ___processor_state ___ps = work->carrier;
  ___WORD *ptr = orig_ptr;
  int fs, link, i;
  ___WORD *fp;
  ___WORD ra1;
  ___WORD ra2;
  ___WORD cf;

  cf = *ptr;

#ifdef SHOW_FRAMES
  ___printf ("mark_captured_continuation cf=%p\n", ___CAST(void*,cf));
#endif

  if (___FIXNUMP(cf) && cf != ___END_OF_CONT_MARKER)
    {
      /* continuation frame is in the stack */

      ___WORD *alloc = work->arena.cursor;
      ___SIZE_TS source_offset=(___MSECTION_SIZE>>1)-
        ___COLLECTION(work->vm).destination_offset;
      ___SIZE_TS half_words;
      ___frame_descriptor frame;
      ___WORD *source, *known_break, *logical_past=0;
      ___msection *section;

      next_frame:

      source=___CAST(___WORD*,cf);
      section=read_source_stack_frame(work,source,source_offset,
                                      logical_past,&ra1,0,&frame,&half_words,&known_break);
      if (!section) {
        rc_contract_error("GC captured frame is outside its source stack grant");
        return;
      }
      fs=frame.fs;
      link=frame.link;
      fp=source+___FRAME_SPACE(fs);
      ra2=___FP_STK(fp,link+1);
      if (!source_break_agrees(fp,known_break,ra2)) {
        rc_contract_error("GC captured successor disagrees with its parked break");
        return;
      }
      if (ra2==___GSTATE->handler_break &&
          half_words-___FRAME_SPACE(fs)<=___BREAK_FRAME_NEXT) {
        rc_contract_error("GC captured break link is outside its source stack grant");
        return;
      }

#ifdef SHOW_FRAMES
        ___printf ("  frame [ra=0x%" ___PRIxWORD "] ", ra1);
#endif

      if (ra1 == ___GSTATE->internal_return) {
        ___COVER_MARK_CAPTURED_CONTINUATION_RETI;
      } else {
        ___COVER_MARK_CAPTURED_CONTINUATION_RETN;
      }

#ifdef SHOW_FRAMES
        ___printf ("fs=%d link=%d fp=%p ra=", fs, link, fp);
        print_value (ra1);
        ___printf ("\n");
#endif

      if (___FIXNUMP(ra2))
        {
          ___COVER_MARK_CAPTURED_CONTINUATION_ALREADY_COPIED;
          *ptr = ra2; /* already copied, replace by forwarding pointer */
          work->frame_links_++;
        }
      else
        {
          ___WORD forw;
          ___WORD *copy_header;
          ___SIZE_TS words;
          ___copy_reservation grant;

          ___COVER_MARK_CAPTURED_CONTINUATION_COPY;

          words = fs + ___FRAME_EXTRA_SLOTS;

          prepare_copy_request(work,section,source,___FRAME_SPACE(fs),words,0,1);
          grant = reserve_copy(work,alloc,words,0);
          alloc = grant.header;

          /*TODO: add allocation of handle if using handles*/

          copy_header = alloc;
          *alloc++ = ___MAKE_HD_WORDS(words, ___sFRAME);
#if ___SUBTYPED_BODY != 1
          #error "___SUBTYPED_BODY != 1"
#endif
          forw = ___TAG(alloc - ___REFERENCE_TO_BODY, ___tFIXNUM);
          *alloc++ = ra1;
#if ___FRAME_EXTRA_SLOTS != 1
          #error "___FRAME_EXTRA_SLOTS != 1"
#endif

          for (i=fs; i>0; i--)
            *alloc++ = ___FP_STK(fp,i);

          if (ra2 == ___GSTATE->handler_break)
            {
              /* first frame of that section */

              ___COVER_MARK_CAPTURED_CONTINUATION_FIRST_FRAME;

              cf = ___FP_STK(fp,-___BREAK_FRAME_NEXT);
              logical_past = 0;
            }
          else
            {
              /* not the first frame of that section */

              ___COVER_MARK_CAPTURED_CONTINUATION_NOT_FIRST_FRAME;

              ___FP_SET_STK(fp,-___FRAME_STACK_RA,ra2)
              cf = ___CAST(___WORD,fp);
              logical_past = known_break;
            }

          ___FP_SET_STK(alloc,link+1,cf)
          ___FP_SET_STK(fp,link+1,forw) /* leave a forwarding pointer */

          *ptr = forw;
          work->frame_links_++;

          record_mature_obj_start(work->arena.section, copy_header);
          publish_object_scan (work, copy_header);
          work->copied_words += words+___SUBTYPED_BODY;
          commit_copy(work,&grant);

          ptr = &___FP_STK(alloc,link+1);

          if (alloc >= alloc_heap_chunk_limit)
            {
              work->arena.cursor = alloc;
              end_heap_chunk (work);
              start_heap_chunk (work);
              alloc = work->arena.cursor;
            }

          if (___FIXNUMP(cf) && cf != ___END_OF_CONT_MARKER)
            goto next_frame;
        }

      *orig_ptr = ___TAG(___UNTAG_AS(*orig_ptr, ___tFIXNUM), ___tSUBTYPED);

      work->arena.cursor = alloc;

    }
  else
    mark_array (work, orig_ptr, 1);
}

___HIDDEN void mark_captured_continuation
   ___P((___collector_worker *work, ___WORD *orig_ptr), (work, orig_ptr)
___collector_worker *work;
___WORD *orig_ptr;)
{
  if(work->census!=0) { census_capture(work,orig_ptr);return; }
  acquire_frame_access(work);
  mark_captured_continuation_locked(work,orig_ptr);
  release_frame_access(work);
}


___HIDDEN void mark_frame
   ___P((___collector_worker *work,
         ___WORD *fp,
         const ___frame_descriptor *frame),
        (work,
         fp,
         frame)
___collector_worker *work;
___WORD *fp;
const ___frame_descriptor *frame;)
{
  ___frame_root_cursor cursor = ___frame_ordinary_root_begin (frame);
  int first, past;

  while (___frame_root_next_run (&cursor, &first, &past))
    {
#ifdef SHOW_FRAMES
      int k = first;
      while (k < past)
        {
          ___WORD obj = ___FP_STK(fp,k);
          ___printf ("  %2d: ", k);
          print_value (obj);
          ___printf ("\n");
          k++;
        }
#endif
      mark_array (work, &___FP_STK(fp,past-1), past-first);
    }
}


___HIDDEN void mark_continuation
   ___P((___collector_worker *work, ___execution_context *context),
        (work, context)
___collector_worker *work;
___execution_context *context;)
{
  ___processor_state ___ps = work->carrier;
  ___frame_descriptor descriptor;
  ___WORD *fp;
  ___WORD ra1;
  ___WORD ra2;
  ___SIZE_TS half_words;
  ___msection *section;
  section_claim *claim;
  ___SIZE_TS source_offset=(___MSECTION_SIZE>>1)-
    ___COLLECTION(work->vm).destination_offset;

  acquire_frame_access(work);
#ifdef ENABLE_CONSISTENCY_CHECKS
  reference_location = IN_CONTINUATION;
#endif

  fp = context->fp;
  section=admit_source_stack_span(work,fp,source_offset,context->stack_break,&half_words);
  claim=section ? section_claim_at(section,source_offset) : 0;
  if (!context->stack_break || !claim || claim->stack_state!=STACK_ACTIVE ||
      claim->stack_owner->context!=context ||
      half_words-(context->stack_break-fp)<=___BREAK_FRAME_NEXT) {
    release_frame_access(work);
    rc_contract_error("GC active break link is outside its source stack grant");
    return;
  }

#ifdef SHOW_FRAMES
  ___printf ("mark_continuation fp=%p\n", fp);
#endif

  if (fp != context->stack_break)
    for (;;)
      {
        if (!decode_source_stack_frame(fp,context->stack_break-fp,&ra1,0,&descriptor)) {
          release_frame_access(work);
          rc_contract_error("GC active frame is outside its source stack grant");
          return;
        }

#ifdef SHOW_FRAMES
        ___printf ("  frame [ra=0x%" ___PRIxWORD "] ", ra1);
#endif

        if (ra1 == ___GSTATE->internal_return)
          {
            ___COVER_MARK_CONTINUATION_RETI;
          }
        else
          {
            ___COVER_MARK_CONTINUATION_RETN;
          }

#ifdef SHOW_FRAMES
        ___printf ("fs=%d link=%d fp=%p ra=", descriptor.fs, descriptor.link, fp);
        print_value (ra1);
        ___printf ("\n");
#endif

        fp+=___FRAME_SPACE(descriptor.fs);

        ra2 = ___FP_STK(fp,descriptor.link+1);

#ifdef SHOW_FRAMES
        if (fp == context->stack_break)
          ___printf ("  (first frame above break frame)\n");
#endif

        mark_frame (work, fp, &descriptor);

        if (fp == context->stack_break)
          break;

        ___FP_SET_STK(fp,-___FRAME_STACK_RA,ra2)
      }

  mark_captured_continuation_locked (work, &___FP_STK(fp,-___BREAK_FRAME_NEXT));
  release_frame_access(work);
}


/* End internal memory fragment. */

___BOOL ___root_task_scan_stack(___root_task *task, ___processor_state executor,
                               ___UWORD epoch)
{
  ___processor_state ___ps=executor;
  ___execution_context *source;
  if (!root_stack_task(task,executor) ||
      !root_task_matches(task,___ROOT_STACK,executor,epoch) ||
      task->state != ___ROOT_CLAIMED || task->scan_leases != 1) return 0;
  source=task->origin.source.stack;
  task->state=___ROOT_SCANNING;
  if(___ps->collector==0 && source->fp==source->stack_break &&
     ___FP_STK(source->stack_break,-___BREAK_FRAME_NEXT)==___END_OF_CONT_MARKER) {
    task->state=___ROOT_SCANNED;return 1;
  }
  if(___ps->collector==0) rc_contract_error("Active frame scan requires a collector worker");
  mark_continuation (___ps->collector, source);
  task->state=___ROOT_SCANNED;
  return 1;
}


/* End internal memory fragment. */
