;;;============================================================================

;;; File: "char-set#.scm"

;;; Copyright (c) 1994-2023 by Marc Feeley, All Rights Reserved.

;;;============================================================================

;;; Representation of character sets.

(##namespace ("" char-set))

;; A char-set has two fields:
;;
;; - boundaries        A u32vector containing the in-out boundaries of the set,
;;                     which is an ordered sequence of all the character codes
;;                     for which the inclusion in the set is different from the
;;                     valid code point immediately preceding it. The sequence
;;                     is constrained to never start with the character
;;                     code 0 and to never contain the code #xd800 (this
;;                     is to guarantee uniqueness of the representation).
;;
;; - hi-lo-complement  Fixnum that combines an 8 bit hi field (bits 9 to 16)
;;                     an 8 bit lo field (bits 1 to 8),
;;                     and a 1 bit complement field (bit 0, the lowest bit).
;;                     The complement field indicates whether the set is
;;                     complemented (1) or not (0).
;;                     When lo=hi=0, only the boundaries field is relevant.
;;                     Otherwise, the hi and lo fields are an alternate
;;                     representation of the char-set that is redundant with
;;                     the boundaries field but quicker to access for
;;                     membership testing. The range lo..hi-1 are the
;;                     values of (u8vector-ref ##unicode-class code)
;;                     indicating membership in the (non-complemented)
;;                     char-set.

(define-type char-set
  id: E15F8CD7-7FF3-4C21-82B9-4355062C112F
  type-exhibitor: macro-type-char-set
  constructor: macro-make-char-set
  constant-constructor: macro-make-constant-char-set
  implementer: implement-type-char-set
  macros:
  prefix: macro-
  opaque:

  (boundaries       unprintable: read-write:)
  (hi-lo-complement unprintable: read-write:)
)

(define-check-type char-set (macro-type-char-set)
  macro-char-set?)

;;;============================================================================
