#ifdef ___LINKER_INFO
; File: "_env.c", produced by Gambit v4.9.8
(
409008
(C)
"_env"
("_env")
()
(("_env"))
( #|*/"*/"symbols|#
"_env"
"_env#"
"c#boolean-decl"
"c#declaration-value"
"c#define-boolean-decl"
"c#define-flag-decl"
"c#define-namable-boolean-decl"
"c#define-namable-decl"
"c#define-parameterized-decl"
"c#env-decl-ref"
"c#env-decl-set"
"c#env-declare"
"c#env-define-var"
"c#env-externals-ref"
"c#env-frame"
"c#env-frame-lookup-var"
"c#env-global-env"
"c#env-global-variables"
"c#env-lookup"
"c#env-lookup-global-var"
"c#env-lookup-macro"
"c#env-lookup-var"
"c#env-macro"
"c#env-macros-ref"
"c#env-macros-set"
"c#env-namespace"
"c#env-namespace-lookup"
"c#env-namespace-lookup-both"
"c#env-namespace-ref"
"c#env-namespace-set"
"c#env-new-var!"
"c#env-parent-ref"
"c#env-vars-ref"
"c#env.begin!"
"c#env.end!"
"c#flag-decl"
"c#full-name?"
"c#macro-list-cached"
"c#macro-list-empty"
"c#macro-list-extend"
"c#macro-list-flatten"
"c#macro-list-overlay-prefix"
"c#macro-list-prefix-length"
"c#macro-list-ref"
"c#macro-list-suffix"
"c#macro-list-table"
"c#make-full-name"
"c#make-temp-var"
"c#make-var"
"c#namable-boolean-decl"
"c#namable-decl"
"c#namespace-valid?"
"c#parameterized-decl"
"c#resize-var-list"
"c#var-bound"
"c#var-bound-set!"
"c#var-boxed?"
"c#var-boxed?-set!"
"c#var-clone"
"c#var-clone-set!"
"c#var-constant"
"c#var-constant-set!"
"c#var-info"
"c#var-info-set!"
"c#var-lexical-level"
"c#var-name"
"c#var-name-set!"
"c#var-refs"
"c#var-refs-set!"
"c#var-sets"
"c#var-sets-set!"
"c#var-source"
"c#var-source-set!"
"c#var-stamp"
"c#var-stamp-set!"
"c#var-temp?"
"c#var-temp?-set!"
"c#var?"
"closure-env"
"macro-index-miss"
"macro-overlay"
"ret"
"var-tag"
) #|*/"*/"symbols|#
( #|*/"*/"keywords|#
"test"
"weak-keys"
) #|*/"*/"keywords|#
( #|*/"*/"globals-s-d|#
"_env#"
"c#boolean-declarations"
"c#empty-var"
"c#env-decl-set"
"c#env-frame"
"c#env-frame-lookup-var"
"c#env-global-env"
"c#env-lookup"
"c#env-macros-set"
"c#env-namespace-lookup"
"c#env-namespace-lookup-both"
"c#env-namespace-set"
"c#env-new-var!"
"c#flag-declarations"
"c#full-name?"
"c#macro-index-miss"
"c#macro-list-cached"
"c#macro-list-empty"
"c#macro-list-extend"
"c#macro-list-flatten"
"c#macro-list-index"
"c#macro-list-overlay-prefix"
"c#macro-list-prefix-length"
"c#macro-list-ref"
"c#macro-list-suffix"
"c#macro-list-table"
"c#make-full-name"
"c#make-temp-var"
"c#make-var"
"c#namable-boolean-declarations"
"c#namable-declarations"
"c#next-var-stamp"
"c#parameterized-declarations"
"c#ret-var"
"c#var-tag"
"c#var?"
) #|*/"*/"globals-s-d|#
( #|*/"*/"globals-s-nd|#
"c#boolean-decl"
"c#closure-env-var"
"c#declaration-value"
"c#define-boolean-decl"
"c#define-flag-decl"
"c#define-namable-boolean-decl"
"c#define-namable-decl"
"c#define-parameterized-decl"
"c#env-decl-ref"
"c#env-declare"
"c#env-define-var"
"c#env-externals-ref"
"c#env-global-variables"
"c#env-lookup-global-var"
"c#env-lookup-macro"
"c#env-lookup-var"
"c#env-macro"
"c#env-macros-ref"
"c#env-namespace"
"c#env-namespace-ref"
"c#env-parent-ref"
"c#env-vars-ref"
"c#env.begin!"
"c#env.end!"
"c#flag-decl"
"c#macro-overlay-limit"
"c#make-global-environment"
"c#namable-boolean-decl"
"c#namable-decl"
"c#namespace-valid?"
"c#parameterized-decl"
"c#resize-var-list"
"c#ret-var-set"
"c#var-bound"
"c#var-bound-set!"
"c#var-boxed?"
"c#var-boxed?-set!"
"c#var-clone"
"c#var-clone-set!"
"c#var-constant"
"c#var-constant-set!"
"c#var-info"
"c#var-info-set!"
"c#var-lexical-level"
"c#var-name"
"c#var-name-set!"
"c#var-refs"
"c#var-refs-set!"
"c#var-sets"
"c#var-sets-set!"
"c#var-source"
"c#var-source-set!"
"c#var-stamp"
"c#var-stamp-set!"
"c#var-temp?"
"c#var-temp?-set!"
) #|*/"*/"globals-s-nd|#
( #|*/"*/"globals-ns|#
"##string->symbol"
"##string-append"
"##symbol->string"
"c#compiler-internal-error"
"c#make-counter"
"c#node-parent"
"c#prc?"
"c#pt-syntax-error"
"c#ptset-empty"
"c#varset-singleton"
"eq?"
"make-table"
"table-for-each"
"table-ref"
"table-set!"
"table?"
) #|*/"*/"globals-ns|#
( #|*/"*/"meta-info|#
) #|*/"*/"meta-info|#
)
#else
#define ___VERSION 409008
#define ___MODULE_NAME "_env"
#define ___LINKER_ID ___LNK___env
#define ___MH_PROC ___H___env
#define ___SCRIPT_LINE 0
#define ___SYMCOUNT 83
#define ___KEYCOUNT 2
#define ___GLOCOUNT 108
#define ___SUPCOUNT 92
#define ___SUBCOUNT 6
#define ___HOST_LAYOUT ___HOST_LAYOUT_PROCEDURES
#define ___LBLCOUNT 425
#define ___OFDCOUNT 10
#define ___MODDESCR ___REF_SUB(3)
#include "gambit.h"

___NEED_SYM(___S___env)
___NEED_SYM(___S___env_23_)
___NEED_SYM(___S_c_23_boolean_2d_decl)
___NEED_SYM(___S_c_23_declaration_2d_value)
___NEED_SYM(___S_c_23_define_2d_boolean_2d_decl)
___NEED_SYM(___S_c_23_define_2d_flag_2d_decl)
___NEED_SYM(___S_c_23_define_2d_namable_2d_boolean_2d_decl)
___NEED_SYM(___S_c_23_define_2d_namable_2d_decl)
___NEED_SYM(___S_c_23_define_2d_parameterized_2d_decl)
___NEED_SYM(___S_c_23_env_2d_decl_2d_ref)
___NEED_SYM(___S_c_23_env_2d_decl_2d_set)
___NEED_SYM(___S_c_23_env_2d_declare)
___NEED_SYM(___S_c_23_env_2d_define_2d_var)
___NEED_SYM(___S_c_23_env_2d_externals_2d_ref)
___NEED_SYM(___S_c_23_env_2d_frame)
___NEED_SYM(___S_c_23_env_2d_frame_2d_lookup_2d_var)
___NEED_SYM(___S_c_23_env_2d_global_2d_env)
___NEED_SYM(___S_c_23_env_2d_global_2d_variables)
___NEED_SYM(___S_c_23_env_2d_lookup)
___NEED_SYM(___S_c_23_env_2d_lookup_2d_global_2d_var)
___NEED_SYM(___S_c_23_env_2d_lookup_2d_macro)
___NEED_SYM(___S_c_23_env_2d_lookup_2d_var)
___NEED_SYM(___S_c_23_env_2d_macro)
___NEED_SYM(___S_c_23_env_2d_macros_2d_ref)
___NEED_SYM(___S_c_23_env_2d_macros_2d_set)
___NEED_SYM(___S_c_23_env_2d_namespace)
___NEED_SYM(___S_c_23_env_2d_namespace_2d_lookup)
___NEED_SYM(___S_c_23_env_2d_namespace_2d_lookup_2d_both)
___NEED_SYM(___S_c_23_env_2d_namespace_2d_ref)
___NEED_SYM(___S_c_23_env_2d_namespace_2d_set)
___NEED_SYM(___S_c_23_env_2d_new_2d_var_21_)
___NEED_SYM(___S_c_23_env_2d_parent_2d_ref)
___NEED_SYM(___S_c_23_env_2d_vars_2d_ref)
___NEED_SYM(___S_c_23_env_2e_begin_21_)
___NEED_SYM(___S_c_23_env_2e_end_21_)
___NEED_SYM(___S_c_23_flag_2d_decl)
___NEED_SYM(___S_c_23_full_2d_name_3f_)
___NEED_SYM(___S_c_23_macro_2d_list_2d_cached)
___NEED_SYM(___S_c_23_macro_2d_list_2d_empty)
___NEED_SYM(___S_c_23_macro_2d_list_2d_extend)
___NEED_SYM(___S_c_23_macro_2d_list_2d_flatten)
___NEED_SYM(___S_c_23_macro_2d_list_2d_overlay_2d_prefix)
___NEED_SYM(___S_c_23_macro_2d_list_2d_prefix_2d_length)
___NEED_SYM(___S_c_23_macro_2d_list_2d_ref)
___NEED_SYM(___S_c_23_macro_2d_list_2d_suffix)
___NEED_SYM(___S_c_23_macro_2d_list_2d_table)
___NEED_SYM(___S_c_23_make_2d_full_2d_name)
___NEED_SYM(___S_c_23_make_2d_temp_2d_var)
___NEED_SYM(___S_c_23_make_2d_var)
___NEED_SYM(___S_c_23_namable_2d_boolean_2d_decl)
___NEED_SYM(___S_c_23_namable_2d_decl)
___NEED_SYM(___S_c_23_namespace_2d_valid_3f_)
___NEED_SYM(___S_c_23_parameterized_2d_decl)
___NEED_SYM(___S_c_23_resize_2d_var_2d_list)
___NEED_SYM(___S_c_23_var_2d_bound)
___NEED_SYM(___S_c_23_var_2d_bound_2d_set_21_)
___NEED_SYM(___S_c_23_var_2d_boxed_3f_)
___NEED_SYM(___S_c_23_var_2d_boxed_3f__2d_set_21_)
___NEED_SYM(___S_c_23_var_2d_clone)
___NEED_SYM(___S_c_23_var_2d_clone_2d_set_21_)
___NEED_SYM(___S_c_23_var_2d_constant)
___NEED_SYM(___S_c_23_var_2d_constant_2d_set_21_)
___NEED_SYM(___S_c_23_var_2d_info)
___NEED_SYM(___S_c_23_var_2d_info_2d_set_21_)
___NEED_SYM(___S_c_23_var_2d_lexical_2d_level)
___NEED_SYM(___S_c_23_var_2d_name)
___NEED_SYM(___S_c_23_var_2d_name_2d_set_21_)
___NEED_SYM(___S_c_23_var_2d_refs)
___NEED_SYM(___S_c_23_var_2d_refs_2d_set_21_)
___NEED_SYM(___S_c_23_var_2d_sets)
___NEED_SYM(___S_c_23_var_2d_sets_2d_set_21_)
___NEED_SYM(___S_c_23_var_2d_source)
___NEED_SYM(___S_c_23_var_2d_source_2d_set_21_)
___NEED_SYM(___S_c_23_var_2d_stamp)
___NEED_SYM(___S_c_23_var_2d_stamp_2d_set_21_)
___NEED_SYM(___S_c_23_var_2d_temp_3f_)
___NEED_SYM(___S_c_23_var_2d_temp_3f__2d_set_21_)
___NEED_SYM(___S_c_23_var_3f_)
___NEED_SYM(___S_closure_2d_env)
___NEED_SYM(___S_macro_2d_index_2d_miss)
___NEED_SYM(___S_macro_2d_overlay)
___NEED_SYM(___S_ret)
___NEED_SYM(___S_var_2d_tag)

___NEED_KEY(___K_test)
___NEED_KEY(___K_weak_2d_keys)

___NEED_GLO(___G__23__23_string_2d__3e_symbol)
___NEED_GLO(___G__23__23_string_2d_append)
___NEED_GLO(___G__23__23_symbol_2d__3e_string)
___NEED_GLO(___G___env_23_)
___NEED_GLO(___G_c_23_boolean_2d_decl)
___NEED_GLO(___G_c_23_boolean_2d_declarations)
___NEED_GLO(___G_c_23_closure_2d_env_2d_var)
___NEED_GLO(___G_c_23_compiler_2d_internal_2d_error)
___NEED_GLO(___G_c_23_declaration_2d_value)
___NEED_GLO(___G_c_23_define_2d_boolean_2d_decl)
___NEED_GLO(___G_c_23_define_2d_flag_2d_decl)
___NEED_GLO(___G_c_23_define_2d_namable_2d_boolean_2d_decl)
___NEED_GLO(___G_c_23_define_2d_namable_2d_decl)
___NEED_GLO(___G_c_23_define_2d_parameterized_2d_decl)
___NEED_GLO(___G_c_23_empty_2d_var)
___NEED_GLO(___G_c_23_env_2d_decl_2d_ref)
___NEED_GLO(___G_c_23_env_2d_decl_2d_set)
___NEED_GLO(___G_c_23_env_2d_declare)
___NEED_GLO(___G_c_23_env_2d_define_2d_var)
___NEED_GLO(___G_c_23_env_2d_externals_2d_ref)
___NEED_GLO(___G_c_23_env_2d_frame)
___NEED_GLO(___G_c_23_env_2d_frame_2d_lookup_2d_var)
___NEED_GLO(___G_c_23_env_2d_global_2d_env)
___NEED_GLO(___G_c_23_env_2d_global_2d_variables)
___NEED_GLO(___G_c_23_env_2d_lookup)
___NEED_GLO(___G_c_23_env_2d_lookup_2d_global_2d_var)
___NEED_GLO(___G_c_23_env_2d_lookup_2d_macro)
___NEED_GLO(___G_c_23_env_2d_lookup_2d_var)
___NEED_GLO(___G_c_23_env_2d_macro)
___NEED_GLO(___G_c_23_env_2d_macros_2d_ref)
___NEED_GLO(___G_c_23_env_2d_macros_2d_set)
___NEED_GLO(___G_c_23_env_2d_namespace)
___NEED_GLO(___G_c_23_env_2d_namespace_2d_lookup)
___NEED_GLO(___G_c_23_env_2d_namespace_2d_lookup_2d_both)
___NEED_GLO(___G_c_23_env_2d_namespace_2d_ref)
___NEED_GLO(___G_c_23_env_2d_namespace_2d_set)
___NEED_GLO(___G_c_23_env_2d_new_2d_var_21_)
___NEED_GLO(___G_c_23_env_2d_parent_2d_ref)
___NEED_GLO(___G_c_23_env_2d_vars_2d_ref)
___NEED_GLO(___G_c_23_env_2e_begin_21_)
___NEED_GLO(___G_c_23_env_2e_end_21_)
___NEED_GLO(___G_c_23_flag_2d_decl)
___NEED_GLO(___G_c_23_flag_2d_declarations)
___NEED_GLO(___G_c_23_full_2d_name_3f_)
___NEED_GLO(___G_c_23_macro_2d_index_2d_miss)
___NEED_GLO(___G_c_23_macro_2d_list_2d_cached)
___NEED_GLO(___G_c_23_macro_2d_list_2d_empty)
___NEED_GLO(___G_c_23_macro_2d_list_2d_extend)
___NEED_GLO(___G_c_23_macro_2d_list_2d_flatten)
___NEED_GLO(___G_c_23_macro_2d_list_2d_index)
___NEED_GLO(___G_c_23_macro_2d_list_2d_overlay_2d_prefix)
___NEED_GLO(___G_c_23_macro_2d_list_2d_prefix_2d_length)
___NEED_GLO(___G_c_23_macro_2d_list_2d_ref)
___NEED_GLO(___G_c_23_macro_2d_list_2d_suffix)
___NEED_GLO(___G_c_23_macro_2d_list_2d_table)
___NEED_GLO(___G_c_23_macro_2d_overlay_2d_limit)
___NEED_GLO(___G_c_23_make_2d_counter)
___NEED_GLO(___G_c_23_make_2d_full_2d_name)
___NEED_GLO(___G_c_23_make_2d_global_2d_environment)
___NEED_GLO(___G_c_23_make_2d_temp_2d_var)
___NEED_GLO(___G_c_23_make_2d_var)
___NEED_GLO(___G_c_23_namable_2d_boolean_2d_decl)
___NEED_GLO(___G_c_23_namable_2d_boolean_2d_declarations)
___NEED_GLO(___G_c_23_namable_2d_decl)
___NEED_GLO(___G_c_23_namable_2d_declarations)
___NEED_GLO(___G_c_23_namespace_2d_valid_3f_)
___NEED_GLO(___G_c_23_next_2d_var_2d_stamp)
___NEED_GLO(___G_c_23_node_2d_parent)
___NEED_GLO(___G_c_23_parameterized_2d_decl)
___NEED_GLO(___G_c_23_parameterized_2d_declarations)
___NEED_GLO(___G_c_23_prc_3f_)
___NEED_GLO(___G_c_23_pt_2d_syntax_2d_error)
___NEED_GLO(___G_c_23_ptset_2d_empty)
___NEED_GLO(___G_c_23_resize_2d_var_2d_list)
___NEED_GLO(___G_c_23_ret_2d_var)
___NEED_GLO(___G_c_23_ret_2d_var_2d_set)
___NEED_GLO(___G_c_23_var_2d_bound)
___NEED_GLO(___G_c_23_var_2d_bound_2d_set_21_)
___NEED_GLO(___G_c_23_var_2d_boxed_3f_)
___NEED_GLO(___G_c_23_var_2d_boxed_3f__2d_set_21_)
___NEED_GLO(___G_c_23_var_2d_clone)
___NEED_GLO(___G_c_23_var_2d_clone_2d_set_21_)
___NEED_GLO(___G_c_23_var_2d_constant)
___NEED_GLO(___G_c_23_var_2d_constant_2d_set_21_)
___NEED_GLO(___G_c_23_var_2d_info)
___NEED_GLO(___G_c_23_var_2d_info_2d_set_21_)
___NEED_GLO(___G_c_23_var_2d_lexical_2d_level)
___NEED_GLO(___G_c_23_var_2d_name)
___NEED_GLO(___G_c_23_var_2d_name_2d_set_21_)
___NEED_GLO(___G_c_23_var_2d_refs)
___NEED_GLO(___G_c_23_var_2d_refs_2d_set_21_)
___NEED_GLO(___G_c_23_var_2d_sets)
___NEED_GLO(___G_c_23_var_2d_sets_2d_set_21_)
___NEED_GLO(___G_c_23_var_2d_source)
___NEED_GLO(___G_c_23_var_2d_source_2d_set_21_)
___NEED_GLO(___G_c_23_var_2d_stamp)
___NEED_GLO(___G_c_23_var_2d_stamp_2d_set_21_)
___NEED_GLO(___G_c_23_var_2d_tag)
___NEED_GLO(___G_c_23_var_2d_temp_3f_)
___NEED_GLO(___G_c_23_var_2d_temp_3f__2d_set_21_)
___NEED_GLO(___G_c_23_var_3f_)
___NEED_GLO(___G_c_23_varset_2d_singleton)
___NEED_GLO(___G_eq_3f_)
___NEED_GLO(___G_make_2d_table)
___NEED_GLO(___G_table_2d_for_2d_each)
___NEED_GLO(___G_table_2d_ref)
___NEED_GLO(___G_table_2d_set_21_)
___NEED_GLO(___G_table_3f_)

___BEGIN_SYM
___DEF_SYM(0,___S___env,"_env")
___DEF_SYM(1,___S___env_23_,"_env#")
___DEF_SYM(2,___S_c_23_boolean_2d_decl,"c#boolean-decl")
___DEF_SYM(3,___S_c_23_declaration_2d_value,"c#declaration-value")
___DEF_SYM(4,___S_c_23_define_2d_boolean_2d_decl,"c#define-boolean-decl")
___DEF_SYM(5,___S_c_23_define_2d_flag_2d_decl,"c#define-flag-decl")
___DEF_SYM(6,___S_c_23_define_2d_namable_2d_boolean_2d_decl,"c#define-namable-boolean-decl")

___DEF_SYM(7,___S_c_23_define_2d_namable_2d_decl,"c#define-namable-decl")
___DEF_SYM(8,___S_c_23_define_2d_parameterized_2d_decl,"c#define-parameterized-decl")
___DEF_SYM(9,___S_c_23_env_2d_decl_2d_ref,"c#env-decl-ref")
___DEF_SYM(10,___S_c_23_env_2d_decl_2d_set,"c#env-decl-set")
___DEF_SYM(11,___S_c_23_env_2d_declare,"c#env-declare")
___DEF_SYM(12,___S_c_23_env_2d_define_2d_var,"c#env-define-var")
___DEF_SYM(13,___S_c_23_env_2d_externals_2d_ref,"c#env-externals-ref")
___DEF_SYM(14,___S_c_23_env_2d_frame,"c#env-frame")
___DEF_SYM(15,___S_c_23_env_2d_frame_2d_lookup_2d_var,"c#env-frame-lookup-var")
___DEF_SYM(16,___S_c_23_env_2d_global_2d_env,"c#env-global-env")
___DEF_SYM(17,___S_c_23_env_2d_global_2d_variables,"c#env-global-variables")
___DEF_SYM(18,___S_c_23_env_2d_lookup,"c#env-lookup")
___DEF_SYM(19,___S_c_23_env_2d_lookup_2d_global_2d_var,"c#env-lookup-global-var")
___DEF_SYM(20,___S_c_23_env_2d_lookup_2d_macro,"c#env-lookup-macro")
___DEF_SYM(21,___S_c_23_env_2d_lookup_2d_var,"c#env-lookup-var")
___DEF_SYM(22,___S_c_23_env_2d_macro,"c#env-macro")
___DEF_SYM(23,___S_c_23_env_2d_macros_2d_ref,"c#env-macros-ref")
___DEF_SYM(24,___S_c_23_env_2d_macros_2d_set,"c#env-macros-set")
___DEF_SYM(25,___S_c_23_env_2d_namespace,"c#env-namespace")
___DEF_SYM(26,___S_c_23_env_2d_namespace_2d_lookup,"c#env-namespace-lookup")
___DEF_SYM(27,___S_c_23_env_2d_namespace_2d_lookup_2d_both,"c#env-namespace-lookup-both")
___DEF_SYM(28,___S_c_23_env_2d_namespace_2d_ref,"c#env-namespace-ref")
___DEF_SYM(29,___S_c_23_env_2d_namespace_2d_set,"c#env-namespace-set")
___DEF_SYM(30,___S_c_23_env_2d_new_2d_var_21_,"c#env-new-var!")
___DEF_SYM(31,___S_c_23_env_2d_parent_2d_ref,"c#env-parent-ref")
___DEF_SYM(32,___S_c_23_env_2d_vars_2d_ref,"c#env-vars-ref")
___DEF_SYM(33,___S_c_23_env_2e_begin_21_,"c#env.begin!")
___DEF_SYM(34,___S_c_23_env_2e_end_21_,"c#env.end!")
___DEF_SYM(35,___S_c_23_flag_2d_decl,"c#flag-decl")
___DEF_SYM(36,___S_c_23_full_2d_name_3f_,"c#full-name?")
___DEF_SYM(37,___S_c_23_macro_2d_list_2d_cached,"c#macro-list-cached")
___DEF_SYM(38,___S_c_23_macro_2d_list_2d_empty,"c#macro-list-empty")
___DEF_SYM(39,___S_c_23_macro_2d_list_2d_extend,"c#macro-list-extend")
___DEF_SYM(40,___S_c_23_macro_2d_list_2d_flatten,"c#macro-list-flatten")
___DEF_SYM(41,___S_c_23_macro_2d_list_2d_overlay_2d_prefix,"c#macro-list-overlay-prefix")
___DEF_SYM(42,___S_c_23_macro_2d_list_2d_prefix_2d_length,"c#macro-list-prefix-length")
___DEF_SYM(43,___S_c_23_macro_2d_list_2d_ref,"c#macro-list-ref")
___DEF_SYM(44,___S_c_23_macro_2d_list_2d_suffix,"c#macro-list-suffix")
___DEF_SYM(45,___S_c_23_macro_2d_list_2d_table,"c#macro-list-table")
___DEF_SYM(46,___S_c_23_make_2d_full_2d_name,"c#make-full-name")
___DEF_SYM(47,___S_c_23_make_2d_temp_2d_var,"c#make-temp-var")
___DEF_SYM(48,___S_c_23_make_2d_var,"c#make-var")
___DEF_SYM(49,___S_c_23_namable_2d_boolean_2d_decl,"c#namable-boolean-decl")
___DEF_SYM(50,___S_c_23_namable_2d_decl,"c#namable-decl")
___DEF_SYM(51,___S_c_23_namespace_2d_valid_3f_,"c#namespace-valid?")
___DEF_SYM(52,___S_c_23_parameterized_2d_decl,"c#parameterized-decl")
___DEF_SYM(53,___S_c_23_resize_2d_var_2d_list,"c#resize-var-list")
___DEF_SYM(54,___S_c_23_var_2d_bound,"c#var-bound")
___DEF_SYM(55,___S_c_23_var_2d_bound_2d_set_21_,"c#var-bound-set!")
___DEF_SYM(56,___S_c_23_var_2d_boxed_3f_,"c#var-boxed?")
___DEF_SYM(57,___S_c_23_var_2d_boxed_3f__2d_set_21_,"c#var-boxed?-set!")
___DEF_SYM(58,___S_c_23_var_2d_clone,"c#var-clone")
___DEF_SYM(59,___S_c_23_var_2d_clone_2d_set_21_,"c#var-clone-set!")
___DEF_SYM(60,___S_c_23_var_2d_constant,"c#var-constant")
___DEF_SYM(61,___S_c_23_var_2d_constant_2d_set_21_,"c#var-constant-set!")
___DEF_SYM(62,___S_c_23_var_2d_info,"c#var-info")
___DEF_SYM(63,___S_c_23_var_2d_info_2d_set_21_,"c#var-info-set!")
___DEF_SYM(64,___S_c_23_var_2d_lexical_2d_level,"c#var-lexical-level")
___DEF_SYM(65,___S_c_23_var_2d_name,"c#var-name")
___DEF_SYM(66,___S_c_23_var_2d_name_2d_set_21_,"c#var-name-set!")
___DEF_SYM(67,___S_c_23_var_2d_refs,"c#var-refs")
___DEF_SYM(68,___S_c_23_var_2d_refs_2d_set_21_,"c#var-refs-set!")
___DEF_SYM(69,___S_c_23_var_2d_sets,"c#var-sets")
___DEF_SYM(70,___S_c_23_var_2d_sets_2d_set_21_,"c#var-sets-set!")
___DEF_SYM(71,___S_c_23_var_2d_source,"c#var-source")
___DEF_SYM(72,___S_c_23_var_2d_source_2d_set_21_,"c#var-source-set!")
___DEF_SYM(73,___S_c_23_var_2d_stamp,"c#var-stamp")
___DEF_SYM(74,___S_c_23_var_2d_stamp_2d_set_21_,"c#var-stamp-set!")
___DEF_SYM(75,___S_c_23_var_2d_temp_3f_,"c#var-temp?")
___DEF_SYM(76,___S_c_23_var_2d_temp_3f__2d_set_21_,"c#var-temp?-set!")
___DEF_SYM(77,___S_c_23_var_3f_,"c#var?")
___DEF_SYM(78,___S_closure_2d_env,"closure-env")
___DEF_SYM(79,___S_macro_2d_index_2d_miss,"macro-index-miss")
___DEF_SYM(80,___S_macro_2d_overlay,"macro-overlay")
___DEF_SYM(81,___S_ret,"ret")
___DEF_SYM(82,___S_var_2d_tag,"var-tag")
___END_SYM

#define ___SYM___env ___SYM(0,___S___env)
#define ___SYM___env_23_ ___SYM(1,___S___env_23_)
#define ___SYM_c_23_boolean_2d_decl ___SYM(2,___S_c_23_boolean_2d_decl)
#define ___SYM_c_23_declaration_2d_value ___SYM(3,___S_c_23_declaration_2d_value)
#define ___SYM_c_23_define_2d_boolean_2d_decl ___SYM(4,___S_c_23_define_2d_boolean_2d_decl)
#define ___SYM_c_23_define_2d_flag_2d_decl ___SYM(5,___S_c_23_define_2d_flag_2d_decl)
#define ___SYM_c_23_define_2d_namable_2d_boolean_2d_decl ___SYM(6,___S_c_23_define_2d_namable_2d_boolean_2d_decl)
#define ___SYM_c_23_define_2d_namable_2d_decl ___SYM(7,___S_c_23_define_2d_namable_2d_decl)
#define ___SYM_c_23_define_2d_parameterized_2d_decl ___SYM(8,___S_c_23_define_2d_parameterized_2d_decl)
#define ___SYM_c_23_env_2d_decl_2d_ref ___SYM(9,___S_c_23_env_2d_decl_2d_ref)
#define ___SYM_c_23_env_2d_decl_2d_set ___SYM(10,___S_c_23_env_2d_decl_2d_set)
#define ___SYM_c_23_env_2d_declare ___SYM(11,___S_c_23_env_2d_declare)
#define ___SYM_c_23_env_2d_define_2d_var ___SYM(12,___S_c_23_env_2d_define_2d_var)
#define ___SYM_c_23_env_2d_externals_2d_ref ___SYM(13,___S_c_23_env_2d_externals_2d_ref)
#define ___SYM_c_23_env_2d_frame ___SYM(14,___S_c_23_env_2d_frame)
#define ___SYM_c_23_env_2d_frame_2d_lookup_2d_var ___SYM(15,___S_c_23_env_2d_frame_2d_lookup_2d_var)
#define ___SYM_c_23_env_2d_global_2d_env ___SYM(16,___S_c_23_env_2d_global_2d_env)
#define ___SYM_c_23_env_2d_global_2d_variables ___SYM(17,___S_c_23_env_2d_global_2d_variables)
#define ___SYM_c_23_env_2d_lookup ___SYM(18,___S_c_23_env_2d_lookup)
#define ___SYM_c_23_env_2d_lookup_2d_global_2d_var ___SYM(19,___S_c_23_env_2d_lookup_2d_global_2d_var)
#define ___SYM_c_23_env_2d_lookup_2d_macro ___SYM(20,___S_c_23_env_2d_lookup_2d_macro)
#define ___SYM_c_23_env_2d_lookup_2d_var ___SYM(21,___S_c_23_env_2d_lookup_2d_var)
#define ___SYM_c_23_env_2d_macro ___SYM(22,___S_c_23_env_2d_macro)
#define ___SYM_c_23_env_2d_macros_2d_ref ___SYM(23,___S_c_23_env_2d_macros_2d_ref)
#define ___SYM_c_23_env_2d_macros_2d_set ___SYM(24,___S_c_23_env_2d_macros_2d_set)
#define ___SYM_c_23_env_2d_namespace ___SYM(25,___S_c_23_env_2d_namespace)
#define ___SYM_c_23_env_2d_namespace_2d_lookup ___SYM(26,___S_c_23_env_2d_namespace_2d_lookup)
#define ___SYM_c_23_env_2d_namespace_2d_lookup_2d_both ___SYM(27,___S_c_23_env_2d_namespace_2d_lookup_2d_both)
#define ___SYM_c_23_env_2d_namespace_2d_ref ___SYM(28,___S_c_23_env_2d_namespace_2d_ref)
#define ___SYM_c_23_env_2d_namespace_2d_set ___SYM(29,___S_c_23_env_2d_namespace_2d_set)
#define ___SYM_c_23_env_2d_new_2d_var_21_ ___SYM(30,___S_c_23_env_2d_new_2d_var_21_)
#define ___SYM_c_23_env_2d_parent_2d_ref ___SYM(31,___S_c_23_env_2d_parent_2d_ref)
#define ___SYM_c_23_env_2d_vars_2d_ref ___SYM(32,___S_c_23_env_2d_vars_2d_ref)
#define ___SYM_c_23_env_2e_begin_21_ ___SYM(33,___S_c_23_env_2e_begin_21_)
#define ___SYM_c_23_env_2e_end_21_ ___SYM(34,___S_c_23_env_2e_end_21_)
#define ___SYM_c_23_flag_2d_decl ___SYM(35,___S_c_23_flag_2d_decl)
#define ___SYM_c_23_full_2d_name_3f_ ___SYM(36,___S_c_23_full_2d_name_3f_)
#define ___SYM_c_23_macro_2d_list_2d_cached ___SYM(37,___S_c_23_macro_2d_list_2d_cached)
#define ___SYM_c_23_macro_2d_list_2d_empty ___SYM(38,___S_c_23_macro_2d_list_2d_empty)
#define ___SYM_c_23_macro_2d_list_2d_extend ___SYM(39,___S_c_23_macro_2d_list_2d_extend)
#define ___SYM_c_23_macro_2d_list_2d_flatten ___SYM(40,___S_c_23_macro_2d_list_2d_flatten)
#define ___SYM_c_23_macro_2d_list_2d_overlay_2d_prefix ___SYM(41,___S_c_23_macro_2d_list_2d_overlay_2d_prefix)
#define ___SYM_c_23_macro_2d_list_2d_prefix_2d_length ___SYM(42,___S_c_23_macro_2d_list_2d_prefix_2d_length)
#define ___SYM_c_23_macro_2d_list_2d_ref ___SYM(43,___S_c_23_macro_2d_list_2d_ref)
#define ___SYM_c_23_macro_2d_list_2d_suffix ___SYM(44,___S_c_23_macro_2d_list_2d_suffix)
#define ___SYM_c_23_macro_2d_list_2d_table ___SYM(45,___S_c_23_macro_2d_list_2d_table)
#define ___SYM_c_23_make_2d_full_2d_name ___SYM(46,___S_c_23_make_2d_full_2d_name)
#define ___SYM_c_23_make_2d_temp_2d_var ___SYM(47,___S_c_23_make_2d_temp_2d_var)
#define ___SYM_c_23_make_2d_var ___SYM(48,___S_c_23_make_2d_var)
#define ___SYM_c_23_namable_2d_boolean_2d_decl ___SYM(49,___S_c_23_namable_2d_boolean_2d_decl)
#define ___SYM_c_23_namable_2d_decl ___SYM(50,___S_c_23_namable_2d_decl)
#define ___SYM_c_23_namespace_2d_valid_3f_ ___SYM(51,___S_c_23_namespace_2d_valid_3f_)
#define ___SYM_c_23_parameterized_2d_decl ___SYM(52,___S_c_23_parameterized_2d_decl)
#define ___SYM_c_23_resize_2d_var_2d_list ___SYM(53,___S_c_23_resize_2d_var_2d_list)
#define ___SYM_c_23_var_2d_bound ___SYM(54,___S_c_23_var_2d_bound)
#define ___SYM_c_23_var_2d_bound_2d_set_21_ ___SYM(55,___S_c_23_var_2d_bound_2d_set_21_)
#define ___SYM_c_23_var_2d_boxed_3f_ ___SYM(56,___S_c_23_var_2d_boxed_3f_)
#define ___SYM_c_23_var_2d_boxed_3f__2d_set_21_ ___SYM(57,___S_c_23_var_2d_boxed_3f__2d_set_21_)
#define ___SYM_c_23_var_2d_clone ___SYM(58,___S_c_23_var_2d_clone)
#define ___SYM_c_23_var_2d_clone_2d_set_21_ ___SYM(59,___S_c_23_var_2d_clone_2d_set_21_)
#define ___SYM_c_23_var_2d_constant ___SYM(60,___S_c_23_var_2d_constant)
#define ___SYM_c_23_var_2d_constant_2d_set_21_ ___SYM(61,___S_c_23_var_2d_constant_2d_set_21_)
#define ___SYM_c_23_var_2d_info ___SYM(62,___S_c_23_var_2d_info)
#define ___SYM_c_23_var_2d_info_2d_set_21_ ___SYM(63,___S_c_23_var_2d_info_2d_set_21_)
#define ___SYM_c_23_var_2d_lexical_2d_level ___SYM(64,___S_c_23_var_2d_lexical_2d_level)
#define ___SYM_c_23_var_2d_name ___SYM(65,___S_c_23_var_2d_name)
#define ___SYM_c_23_var_2d_name_2d_set_21_ ___SYM(66,___S_c_23_var_2d_name_2d_set_21_)
#define ___SYM_c_23_var_2d_refs ___SYM(67,___S_c_23_var_2d_refs)
#define ___SYM_c_23_var_2d_refs_2d_set_21_ ___SYM(68,___S_c_23_var_2d_refs_2d_set_21_)
#define ___SYM_c_23_var_2d_sets ___SYM(69,___S_c_23_var_2d_sets)
#define ___SYM_c_23_var_2d_sets_2d_set_21_ ___SYM(70,___S_c_23_var_2d_sets_2d_set_21_)
#define ___SYM_c_23_var_2d_source ___SYM(71,___S_c_23_var_2d_source)
#define ___SYM_c_23_var_2d_source_2d_set_21_ ___SYM(72,___S_c_23_var_2d_source_2d_set_21_)
#define ___SYM_c_23_var_2d_stamp ___SYM(73,___S_c_23_var_2d_stamp)
#define ___SYM_c_23_var_2d_stamp_2d_set_21_ ___SYM(74,___S_c_23_var_2d_stamp_2d_set_21_)
#define ___SYM_c_23_var_2d_temp_3f_ ___SYM(75,___S_c_23_var_2d_temp_3f_)
#define ___SYM_c_23_var_2d_temp_3f__2d_set_21_ ___SYM(76,___S_c_23_var_2d_temp_3f__2d_set_21_)
#define ___SYM_c_23_var_3f_ ___SYM(77,___S_c_23_var_3f_)
#define ___SYM_closure_2d_env ___SYM(78,___S_closure_2d_env)
#define ___SYM_macro_2d_index_2d_miss ___SYM(79,___S_macro_2d_index_2d_miss)
#define ___SYM_macro_2d_overlay ___SYM(80,___S_macro_2d_overlay)
#define ___SYM_ret ___SYM(81,___S_ret)
#define ___SYM_var_2d_tag ___SYM(82,___S_var_2d_tag)

___BEGIN_KEY
___DEF_KEY(0,___K_test,"test")
___DEF_KEY(1,___K_weak_2d_keys,"weak-keys")
___END_KEY

#define ___KEY_test ___KEY(0,___K_test)
#define ___KEY_weak_2d_keys ___KEY(1,___K_weak_2d_keys)

___BEGIN_GLO
___DEF_GLO(0,"_env#")
___DEF_GLO(1,"c#boolean-decl")
___DEF_GLO(2,"c#boolean-declarations")
___DEF_GLO(3,"c#closure-env-var")
___DEF_GLO(4,"c#declaration-value")
___DEF_GLO(5,"c#define-boolean-decl")
___DEF_GLO(6,"c#define-flag-decl")
___DEF_GLO(7,"c#define-namable-boolean-decl")
___DEF_GLO(8,"c#define-namable-decl")
___DEF_GLO(9,"c#define-parameterized-decl")
___DEF_GLO(10,"c#empty-var")
___DEF_GLO(11,"c#env-decl-ref")
___DEF_GLO(12,"c#env-decl-set")
___DEF_GLO(13,"c#env-declare")
___DEF_GLO(14,"c#env-define-var")
___DEF_GLO(15,"c#env-externals-ref")
___DEF_GLO(16,"c#env-frame")
___DEF_GLO(17,"c#env-frame-lookup-var")
___DEF_GLO(18,"c#env-global-env")
___DEF_GLO(19,"c#env-global-variables")
___DEF_GLO(20,"c#env-lookup")
___DEF_GLO(21,"c#env-lookup-global-var")
___DEF_GLO(22,"c#env-lookup-macro")
___DEF_GLO(23,"c#env-lookup-var")
___DEF_GLO(24,"c#env-macro")
___DEF_GLO(25,"c#env-macros-ref")
___DEF_GLO(26,"c#env-macros-set")
___DEF_GLO(27,"c#env-namespace")
___DEF_GLO(28,"c#env-namespace-lookup")
___DEF_GLO(29,"c#env-namespace-lookup-both")
___DEF_GLO(30,"c#env-namespace-ref")
___DEF_GLO(31,"c#env-namespace-set")
___DEF_GLO(32,"c#env-new-var!")
___DEF_GLO(33,"c#env-parent-ref")
___DEF_GLO(34,"c#env-vars-ref")
___DEF_GLO(35,"c#env.begin!")
___DEF_GLO(36,"c#env.end!")
___DEF_GLO(37,"c#flag-decl")
___DEF_GLO(38,"c#flag-declarations")
___DEF_GLO(39,"c#full-name?")
___DEF_GLO(40,"c#macro-index-miss")
___DEF_GLO(41,"c#macro-list-cached")
___DEF_GLO(42,"c#macro-list-empty")
___DEF_GLO(43,"c#macro-list-extend")
___DEF_GLO(44,"c#macro-list-flatten")
___DEF_GLO(45,"c#macro-list-index")
___DEF_GLO(46,"c#macro-list-overlay-prefix")
___DEF_GLO(47,"c#macro-list-prefix-length")
___DEF_GLO(48,"c#macro-list-ref")
___DEF_GLO(49,"c#macro-list-suffix")
___DEF_GLO(50,"c#macro-list-table")
___DEF_GLO(51,"c#macro-overlay-limit")
___DEF_GLO(52,"c#make-full-name")
___DEF_GLO(53,"c#make-global-environment")
___DEF_GLO(54,"c#make-temp-var")
___DEF_GLO(55,"c#make-var")
___DEF_GLO(56,"c#namable-boolean-decl")
___DEF_GLO(57,"c#namable-boolean-declarations")
___DEF_GLO(58,"c#namable-decl")
___DEF_GLO(59,"c#namable-declarations")
___DEF_GLO(60,"c#namespace-valid?")
___DEF_GLO(61,"c#next-var-stamp")
___DEF_GLO(62,"c#parameterized-decl")
___DEF_GLO(63,"c#parameterized-declarations")
___DEF_GLO(64,"c#resize-var-list")
___DEF_GLO(65,"c#ret-var")
___DEF_GLO(66,"c#ret-var-set")
___DEF_GLO(67,"c#var-bound")
___DEF_GLO(68,"c#var-bound-set!")
___DEF_GLO(69,"c#var-boxed?")
___DEF_GLO(70,"c#var-boxed?-set!")
___DEF_GLO(71,"c#var-clone")
___DEF_GLO(72,"c#var-clone-set!")
___DEF_GLO(73,"c#var-constant")
___DEF_GLO(74,"c#var-constant-set!")
___DEF_GLO(75,"c#var-info")
___DEF_GLO(76,"c#var-info-set!")
___DEF_GLO(77,"c#var-lexical-level")
___DEF_GLO(78,"c#var-name")
___DEF_GLO(79,"c#var-name-set!")
___DEF_GLO(80,"c#var-refs")
___DEF_GLO(81,"c#var-refs-set!")
___DEF_GLO(82,"c#var-sets")
___DEF_GLO(83,"c#var-sets-set!")
___DEF_GLO(84,"c#var-source")
___DEF_GLO(85,"c#var-source-set!")
___DEF_GLO(86,"c#var-stamp")
___DEF_GLO(87,"c#var-stamp-set!")
___DEF_GLO(88,"c#var-tag")
___DEF_GLO(89,"c#var-temp?")
___DEF_GLO(90,"c#var-temp?-set!")
___DEF_GLO(91,"c#var?")
___DEF_GLO(92,"##string->symbol")
___DEF_GLO(93,"##string-append")
___DEF_GLO(94,"##symbol->string")
___DEF_GLO(95,"c#compiler-internal-error")
___DEF_GLO(96,"c#make-counter")
___DEF_GLO(97,"c#node-parent")
___DEF_GLO(98,"c#prc?")
___DEF_GLO(99,"c#pt-syntax-error")
___DEF_GLO(100,"c#ptset-empty")
___DEF_GLO(101,"c#varset-singleton")
___DEF_GLO(102,"eq?")
___DEF_GLO(103,"make-table")
___DEF_GLO(104,"table-for-each")
___DEF_GLO(105,"table-ref")
___DEF_GLO(106,"table-set!")
___DEF_GLO(107,"table?")
___END_GLO

#define ___GLO___env_23_ ___GLO(0,___G___env_23_)
#define ___PRM___env_23_ ___PRM(0,___G___env_23_)
#define ___GLO_c_23_boolean_2d_decl ___GLO(1,___G_c_23_boolean_2d_decl)
#define ___PRM_c_23_boolean_2d_decl ___PRM(1,___G_c_23_boolean_2d_decl)
#define ___GLO_c_23_boolean_2d_declarations ___GLO(2,___G_c_23_boolean_2d_declarations)
#define ___PRM_c_23_boolean_2d_declarations ___PRM(2,___G_c_23_boolean_2d_declarations)
#define ___GLO_c_23_closure_2d_env_2d_var ___GLO(3,___G_c_23_closure_2d_env_2d_var)
#define ___PRM_c_23_closure_2d_env_2d_var ___PRM(3,___G_c_23_closure_2d_env_2d_var)
#define ___GLO_c_23_declaration_2d_value ___GLO(4,___G_c_23_declaration_2d_value)
#define ___PRM_c_23_declaration_2d_value ___PRM(4,___G_c_23_declaration_2d_value)
#define ___GLO_c_23_define_2d_boolean_2d_decl ___GLO(5,___G_c_23_define_2d_boolean_2d_decl)
#define ___PRM_c_23_define_2d_boolean_2d_decl ___PRM(5,___G_c_23_define_2d_boolean_2d_decl)
#define ___GLO_c_23_define_2d_flag_2d_decl ___GLO(6,___G_c_23_define_2d_flag_2d_decl)
#define ___PRM_c_23_define_2d_flag_2d_decl ___PRM(6,___G_c_23_define_2d_flag_2d_decl)
#define ___GLO_c_23_define_2d_namable_2d_boolean_2d_decl ___GLO(7,___G_c_23_define_2d_namable_2d_boolean_2d_decl)
#define ___PRM_c_23_define_2d_namable_2d_boolean_2d_decl ___PRM(7,___G_c_23_define_2d_namable_2d_boolean_2d_decl)
#define ___GLO_c_23_define_2d_namable_2d_decl ___GLO(8,___G_c_23_define_2d_namable_2d_decl)
#define ___PRM_c_23_define_2d_namable_2d_decl ___PRM(8,___G_c_23_define_2d_namable_2d_decl)
#define ___GLO_c_23_define_2d_parameterized_2d_decl ___GLO(9,___G_c_23_define_2d_parameterized_2d_decl)
#define ___PRM_c_23_define_2d_parameterized_2d_decl ___PRM(9,___G_c_23_define_2d_parameterized_2d_decl)
#define ___GLO_c_23_empty_2d_var ___GLO(10,___G_c_23_empty_2d_var)
#define ___PRM_c_23_empty_2d_var ___PRM(10,___G_c_23_empty_2d_var)
#define ___GLO_c_23_env_2d_decl_2d_ref ___GLO(11,___G_c_23_env_2d_decl_2d_ref)
#define ___PRM_c_23_env_2d_decl_2d_ref ___PRM(11,___G_c_23_env_2d_decl_2d_ref)
#define ___GLO_c_23_env_2d_decl_2d_set ___GLO(12,___G_c_23_env_2d_decl_2d_set)
#define ___PRM_c_23_env_2d_decl_2d_set ___PRM(12,___G_c_23_env_2d_decl_2d_set)
#define ___GLO_c_23_env_2d_declare ___GLO(13,___G_c_23_env_2d_declare)
#define ___PRM_c_23_env_2d_declare ___PRM(13,___G_c_23_env_2d_declare)
#define ___GLO_c_23_env_2d_define_2d_var ___GLO(14,___G_c_23_env_2d_define_2d_var)
#define ___PRM_c_23_env_2d_define_2d_var ___PRM(14,___G_c_23_env_2d_define_2d_var)
#define ___GLO_c_23_env_2d_externals_2d_ref ___GLO(15,___G_c_23_env_2d_externals_2d_ref)
#define ___PRM_c_23_env_2d_externals_2d_ref ___PRM(15,___G_c_23_env_2d_externals_2d_ref)
#define ___GLO_c_23_env_2d_frame ___GLO(16,___G_c_23_env_2d_frame)
#define ___PRM_c_23_env_2d_frame ___PRM(16,___G_c_23_env_2d_frame)
#define ___GLO_c_23_env_2d_frame_2d_lookup_2d_var ___GLO(17,___G_c_23_env_2d_frame_2d_lookup_2d_var)
#define ___PRM_c_23_env_2d_frame_2d_lookup_2d_var ___PRM(17,___G_c_23_env_2d_frame_2d_lookup_2d_var)
#define ___GLO_c_23_env_2d_global_2d_env ___GLO(18,___G_c_23_env_2d_global_2d_env)
#define ___PRM_c_23_env_2d_global_2d_env ___PRM(18,___G_c_23_env_2d_global_2d_env)
#define ___GLO_c_23_env_2d_global_2d_variables ___GLO(19,___G_c_23_env_2d_global_2d_variables)
#define ___PRM_c_23_env_2d_global_2d_variables ___PRM(19,___G_c_23_env_2d_global_2d_variables)
#define ___GLO_c_23_env_2d_lookup ___GLO(20,___G_c_23_env_2d_lookup)
#define ___PRM_c_23_env_2d_lookup ___PRM(20,___G_c_23_env_2d_lookup)
#define ___GLO_c_23_env_2d_lookup_2d_global_2d_var ___GLO(21,___G_c_23_env_2d_lookup_2d_global_2d_var)
#define ___PRM_c_23_env_2d_lookup_2d_global_2d_var ___PRM(21,___G_c_23_env_2d_lookup_2d_global_2d_var)
#define ___GLO_c_23_env_2d_lookup_2d_macro ___GLO(22,___G_c_23_env_2d_lookup_2d_macro)
#define ___PRM_c_23_env_2d_lookup_2d_macro ___PRM(22,___G_c_23_env_2d_lookup_2d_macro)
#define ___GLO_c_23_env_2d_lookup_2d_var ___GLO(23,___G_c_23_env_2d_lookup_2d_var)
#define ___PRM_c_23_env_2d_lookup_2d_var ___PRM(23,___G_c_23_env_2d_lookup_2d_var)
#define ___GLO_c_23_env_2d_macro ___GLO(24,___G_c_23_env_2d_macro)
#define ___PRM_c_23_env_2d_macro ___PRM(24,___G_c_23_env_2d_macro)
#define ___GLO_c_23_env_2d_macros_2d_ref ___GLO(25,___G_c_23_env_2d_macros_2d_ref)
#define ___PRM_c_23_env_2d_macros_2d_ref ___PRM(25,___G_c_23_env_2d_macros_2d_ref)
#define ___GLO_c_23_env_2d_macros_2d_set ___GLO(26,___G_c_23_env_2d_macros_2d_set)
#define ___PRM_c_23_env_2d_macros_2d_set ___PRM(26,___G_c_23_env_2d_macros_2d_set)
#define ___GLO_c_23_env_2d_namespace ___GLO(27,___G_c_23_env_2d_namespace)
#define ___PRM_c_23_env_2d_namespace ___PRM(27,___G_c_23_env_2d_namespace)
#define ___GLO_c_23_env_2d_namespace_2d_lookup ___GLO(28,___G_c_23_env_2d_namespace_2d_lookup)
#define ___PRM_c_23_env_2d_namespace_2d_lookup ___PRM(28,___G_c_23_env_2d_namespace_2d_lookup)
#define ___GLO_c_23_env_2d_namespace_2d_lookup_2d_both ___GLO(29,___G_c_23_env_2d_namespace_2d_lookup_2d_both)
#define ___PRM_c_23_env_2d_namespace_2d_lookup_2d_both ___PRM(29,___G_c_23_env_2d_namespace_2d_lookup_2d_both)
#define ___GLO_c_23_env_2d_namespace_2d_ref ___GLO(30,___G_c_23_env_2d_namespace_2d_ref)
#define ___PRM_c_23_env_2d_namespace_2d_ref ___PRM(30,___G_c_23_env_2d_namespace_2d_ref)
#define ___GLO_c_23_env_2d_namespace_2d_set ___GLO(31,___G_c_23_env_2d_namespace_2d_set)
#define ___PRM_c_23_env_2d_namespace_2d_set ___PRM(31,___G_c_23_env_2d_namespace_2d_set)
#define ___GLO_c_23_env_2d_new_2d_var_21_ ___GLO(32,___G_c_23_env_2d_new_2d_var_21_)
#define ___PRM_c_23_env_2d_new_2d_var_21_ ___PRM(32,___G_c_23_env_2d_new_2d_var_21_)
#define ___GLO_c_23_env_2d_parent_2d_ref ___GLO(33,___G_c_23_env_2d_parent_2d_ref)
#define ___PRM_c_23_env_2d_parent_2d_ref ___PRM(33,___G_c_23_env_2d_parent_2d_ref)
#define ___GLO_c_23_env_2d_vars_2d_ref ___GLO(34,___G_c_23_env_2d_vars_2d_ref)
#define ___PRM_c_23_env_2d_vars_2d_ref ___PRM(34,___G_c_23_env_2d_vars_2d_ref)
#define ___GLO_c_23_env_2e_begin_21_ ___GLO(35,___G_c_23_env_2e_begin_21_)
#define ___PRM_c_23_env_2e_begin_21_ ___PRM(35,___G_c_23_env_2e_begin_21_)
#define ___GLO_c_23_env_2e_end_21_ ___GLO(36,___G_c_23_env_2e_end_21_)
#define ___PRM_c_23_env_2e_end_21_ ___PRM(36,___G_c_23_env_2e_end_21_)
#define ___GLO_c_23_flag_2d_decl ___GLO(37,___G_c_23_flag_2d_decl)
#define ___PRM_c_23_flag_2d_decl ___PRM(37,___G_c_23_flag_2d_decl)
#define ___GLO_c_23_flag_2d_declarations ___GLO(38,___G_c_23_flag_2d_declarations)
#define ___PRM_c_23_flag_2d_declarations ___PRM(38,___G_c_23_flag_2d_declarations)
#define ___GLO_c_23_full_2d_name_3f_ ___GLO(39,___G_c_23_full_2d_name_3f_)
#define ___PRM_c_23_full_2d_name_3f_ ___PRM(39,___G_c_23_full_2d_name_3f_)
#define ___GLO_c_23_macro_2d_index_2d_miss ___GLO(40,___G_c_23_macro_2d_index_2d_miss)
#define ___PRM_c_23_macro_2d_index_2d_miss ___PRM(40,___G_c_23_macro_2d_index_2d_miss)
#define ___GLO_c_23_macro_2d_list_2d_cached ___GLO(41,___G_c_23_macro_2d_list_2d_cached)
#define ___PRM_c_23_macro_2d_list_2d_cached ___PRM(41,___G_c_23_macro_2d_list_2d_cached)
#define ___GLO_c_23_macro_2d_list_2d_empty ___GLO(42,___G_c_23_macro_2d_list_2d_empty)
#define ___PRM_c_23_macro_2d_list_2d_empty ___PRM(42,___G_c_23_macro_2d_list_2d_empty)
#define ___GLO_c_23_macro_2d_list_2d_extend ___GLO(43,___G_c_23_macro_2d_list_2d_extend)
#define ___PRM_c_23_macro_2d_list_2d_extend ___PRM(43,___G_c_23_macro_2d_list_2d_extend)
#define ___GLO_c_23_macro_2d_list_2d_flatten ___GLO(44,___G_c_23_macro_2d_list_2d_flatten)
#define ___PRM_c_23_macro_2d_list_2d_flatten ___PRM(44,___G_c_23_macro_2d_list_2d_flatten)
#define ___GLO_c_23_macro_2d_list_2d_index ___GLO(45,___G_c_23_macro_2d_list_2d_index)
#define ___PRM_c_23_macro_2d_list_2d_index ___PRM(45,___G_c_23_macro_2d_list_2d_index)
#define ___GLO_c_23_macro_2d_list_2d_overlay_2d_prefix ___GLO(46,___G_c_23_macro_2d_list_2d_overlay_2d_prefix)
#define ___PRM_c_23_macro_2d_list_2d_overlay_2d_prefix ___PRM(46,___G_c_23_macro_2d_list_2d_overlay_2d_prefix)
#define ___GLO_c_23_macro_2d_list_2d_prefix_2d_length ___GLO(47,___G_c_23_macro_2d_list_2d_prefix_2d_length)
#define ___PRM_c_23_macro_2d_list_2d_prefix_2d_length ___PRM(47,___G_c_23_macro_2d_list_2d_prefix_2d_length)
#define ___GLO_c_23_macro_2d_list_2d_ref ___GLO(48,___G_c_23_macro_2d_list_2d_ref)
#define ___PRM_c_23_macro_2d_list_2d_ref ___PRM(48,___G_c_23_macro_2d_list_2d_ref)
#define ___GLO_c_23_macro_2d_list_2d_suffix ___GLO(49,___G_c_23_macro_2d_list_2d_suffix)
#define ___PRM_c_23_macro_2d_list_2d_suffix ___PRM(49,___G_c_23_macro_2d_list_2d_suffix)
#define ___GLO_c_23_macro_2d_list_2d_table ___GLO(50,___G_c_23_macro_2d_list_2d_table)
#define ___PRM_c_23_macro_2d_list_2d_table ___PRM(50,___G_c_23_macro_2d_list_2d_table)
#define ___GLO_c_23_macro_2d_overlay_2d_limit ___GLO(51,___G_c_23_macro_2d_overlay_2d_limit)
#define ___PRM_c_23_macro_2d_overlay_2d_limit ___PRM(51,___G_c_23_macro_2d_overlay_2d_limit)
#define ___GLO_c_23_make_2d_full_2d_name ___GLO(52,___G_c_23_make_2d_full_2d_name)
#define ___PRM_c_23_make_2d_full_2d_name ___PRM(52,___G_c_23_make_2d_full_2d_name)
#define ___GLO_c_23_make_2d_global_2d_environment ___GLO(53,___G_c_23_make_2d_global_2d_environment)
#define ___PRM_c_23_make_2d_global_2d_environment ___PRM(53,___G_c_23_make_2d_global_2d_environment)
#define ___GLO_c_23_make_2d_temp_2d_var ___GLO(54,___G_c_23_make_2d_temp_2d_var)
#define ___PRM_c_23_make_2d_temp_2d_var ___PRM(54,___G_c_23_make_2d_temp_2d_var)
#define ___GLO_c_23_make_2d_var ___GLO(55,___G_c_23_make_2d_var)
#define ___PRM_c_23_make_2d_var ___PRM(55,___G_c_23_make_2d_var)
#define ___GLO_c_23_namable_2d_boolean_2d_decl ___GLO(56,___G_c_23_namable_2d_boolean_2d_decl)
#define ___PRM_c_23_namable_2d_boolean_2d_decl ___PRM(56,___G_c_23_namable_2d_boolean_2d_decl)
#define ___GLO_c_23_namable_2d_boolean_2d_declarations ___GLO(57,___G_c_23_namable_2d_boolean_2d_declarations)
#define ___PRM_c_23_namable_2d_boolean_2d_declarations ___PRM(57,___G_c_23_namable_2d_boolean_2d_declarations)
#define ___GLO_c_23_namable_2d_decl ___GLO(58,___G_c_23_namable_2d_decl)
#define ___PRM_c_23_namable_2d_decl ___PRM(58,___G_c_23_namable_2d_decl)
#define ___GLO_c_23_namable_2d_declarations ___GLO(59,___G_c_23_namable_2d_declarations)
#define ___PRM_c_23_namable_2d_declarations ___PRM(59,___G_c_23_namable_2d_declarations)
#define ___GLO_c_23_namespace_2d_valid_3f_ ___GLO(60,___G_c_23_namespace_2d_valid_3f_)
#define ___PRM_c_23_namespace_2d_valid_3f_ ___PRM(60,___G_c_23_namespace_2d_valid_3f_)
#define ___GLO_c_23_next_2d_var_2d_stamp ___GLO(61,___G_c_23_next_2d_var_2d_stamp)
#define ___PRM_c_23_next_2d_var_2d_stamp ___PRM(61,___G_c_23_next_2d_var_2d_stamp)
#define ___GLO_c_23_parameterized_2d_decl ___GLO(62,___G_c_23_parameterized_2d_decl)
#define ___PRM_c_23_parameterized_2d_decl ___PRM(62,___G_c_23_parameterized_2d_decl)
#define ___GLO_c_23_parameterized_2d_declarations ___GLO(63,___G_c_23_parameterized_2d_declarations)
#define ___PRM_c_23_parameterized_2d_declarations ___PRM(63,___G_c_23_parameterized_2d_declarations)
#define ___GLO_c_23_resize_2d_var_2d_list ___GLO(64,___G_c_23_resize_2d_var_2d_list)
#define ___PRM_c_23_resize_2d_var_2d_list ___PRM(64,___G_c_23_resize_2d_var_2d_list)
#define ___GLO_c_23_ret_2d_var ___GLO(65,___G_c_23_ret_2d_var)
#define ___PRM_c_23_ret_2d_var ___PRM(65,___G_c_23_ret_2d_var)
#define ___GLO_c_23_ret_2d_var_2d_set ___GLO(66,___G_c_23_ret_2d_var_2d_set)
#define ___PRM_c_23_ret_2d_var_2d_set ___PRM(66,___G_c_23_ret_2d_var_2d_set)
#define ___GLO_c_23_var_2d_bound ___GLO(67,___G_c_23_var_2d_bound)
#define ___PRM_c_23_var_2d_bound ___PRM(67,___G_c_23_var_2d_bound)
#define ___GLO_c_23_var_2d_bound_2d_set_21_ ___GLO(68,___G_c_23_var_2d_bound_2d_set_21_)
#define ___PRM_c_23_var_2d_bound_2d_set_21_ ___PRM(68,___G_c_23_var_2d_bound_2d_set_21_)
#define ___GLO_c_23_var_2d_boxed_3f_ ___GLO(69,___G_c_23_var_2d_boxed_3f_)
#define ___PRM_c_23_var_2d_boxed_3f_ ___PRM(69,___G_c_23_var_2d_boxed_3f_)
#define ___GLO_c_23_var_2d_boxed_3f__2d_set_21_ ___GLO(70,___G_c_23_var_2d_boxed_3f__2d_set_21_)
#define ___PRM_c_23_var_2d_boxed_3f__2d_set_21_ ___PRM(70,___G_c_23_var_2d_boxed_3f__2d_set_21_)
#define ___GLO_c_23_var_2d_clone ___GLO(71,___G_c_23_var_2d_clone)
#define ___PRM_c_23_var_2d_clone ___PRM(71,___G_c_23_var_2d_clone)
#define ___GLO_c_23_var_2d_clone_2d_set_21_ ___GLO(72,___G_c_23_var_2d_clone_2d_set_21_)
#define ___PRM_c_23_var_2d_clone_2d_set_21_ ___PRM(72,___G_c_23_var_2d_clone_2d_set_21_)
#define ___GLO_c_23_var_2d_constant ___GLO(73,___G_c_23_var_2d_constant)
#define ___PRM_c_23_var_2d_constant ___PRM(73,___G_c_23_var_2d_constant)
#define ___GLO_c_23_var_2d_constant_2d_set_21_ ___GLO(74,___G_c_23_var_2d_constant_2d_set_21_)
#define ___PRM_c_23_var_2d_constant_2d_set_21_ ___PRM(74,___G_c_23_var_2d_constant_2d_set_21_)
#define ___GLO_c_23_var_2d_info ___GLO(75,___G_c_23_var_2d_info)
#define ___PRM_c_23_var_2d_info ___PRM(75,___G_c_23_var_2d_info)
#define ___GLO_c_23_var_2d_info_2d_set_21_ ___GLO(76,___G_c_23_var_2d_info_2d_set_21_)
#define ___PRM_c_23_var_2d_info_2d_set_21_ ___PRM(76,___G_c_23_var_2d_info_2d_set_21_)
#define ___GLO_c_23_var_2d_lexical_2d_level ___GLO(77,___G_c_23_var_2d_lexical_2d_level)
#define ___PRM_c_23_var_2d_lexical_2d_level ___PRM(77,___G_c_23_var_2d_lexical_2d_level)
#define ___GLO_c_23_var_2d_name ___GLO(78,___G_c_23_var_2d_name)
#define ___PRM_c_23_var_2d_name ___PRM(78,___G_c_23_var_2d_name)
#define ___GLO_c_23_var_2d_name_2d_set_21_ ___GLO(79,___G_c_23_var_2d_name_2d_set_21_)
#define ___PRM_c_23_var_2d_name_2d_set_21_ ___PRM(79,___G_c_23_var_2d_name_2d_set_21_)
#define ___GLO_c_23_var_2d_refs ___GLO(80,___G_c_23_var_2d_refs)
#define ___PRM_c_23_var_2d_refs ___PRM(80,___G_c_23_var_2d_refs)
#define ___GLO_c_23_var_2d_refs_2d_set_21_ ___GLO(81,___G_c_23_var_2d_refs_2d_set_21_)
#define ___PRM_c_23_var_2d_refs_2d_set_21_ ___PRM(81,___G_c_23_var_2d_refs_2d_set_21_)
#define ___GLO_c_23_var_2d_sets ___GLO(82,___G_c_23_var_2d_sets)
#define ___PRM_c_23_var_2d_sets ___PRM(82,___G_c_23_var_2d_sets)
#define ___GLO_c_23_var_2d_sets_2d_set_21_ ___GLO(83,___G_c_23_var_2d_sets_2d_set_21_)
#define ___PRM_c_23_var_2d_sets_2d_set_21_ ___PRM(83,___G_c_23_var_2d_sets_2d_set_21_)
#define ___GLO_c_23_var_2d_source ___GLO(84,___G_c_23_var_2d_source)
#define ___PRM_c_23_var_2d_source ___PRM(84,___G_c_23_var_2d_source)
#define ___GLO_c_23_var_2d_source_2d_set_21_ ___GLO(85,___G_c_23_var_2d_source_2d_set_21_)
#define ___PRM_c_23_var_2d_source_2d_set_21_ ___PRM(85,___G_c_23_var_2d_source_2d_set_21_)
#define ___GLO_c_23_var_2d_stamp ___GLO(86,___G_c_23_var_2d_stamp)
#define ___PRM_c_23_var_2d_stamp ___PRM(86,___G_c_23_var_2d_stamp)
#define ___GLO_c_23_var_2d_stamp_2d_set_21_ ___GLO(87,___G_c_23_var_2d_stamp_2d_set_21_)
#define ___PRM_c_23_var_2d_stamp_2d_set_21_ ___PRM(87,___G_c_23_var_2d_stamp_2d_set_21_)
#define ___GLO_c_23_var_2d_tag ___GLO(88,___G_c_23_var_2d_tag)
#define ___PRM_c_23_var_2d_tag ___PRM(88,___G_c_23_var_2d_tag)
#define ___GLO_c_23_var_2d_temp_3f_ ___GLO(89,___G_c_23_var_2d_temp_3f_)
#define ___PRM_c_23_var_2d_temp_3f_ ___PRM(89,___G_c_23_var_2d_temp_3f_)
#define ___GLO_c_23_var_2d_temp_3f__2d_set_21_ ___GLO(90,___G_c_23_var_2d_temp_3f__2d_set_21_)
#define ___PRM_c_23_var_2d_temp_3f__2d_set_21_ ___PRM(90,___G_c_23_var_2d_temp_3f__2d_set_21_)
#define ___GLO_c_23_var_3f_ ___GLO(91,___G_c_23_var_3f_)
#define ___PRM_c_23_var_3f_ ___PRM(91,___G_c_23_var_3f_)
#define ___GLO__23__23_string_2d__3e_symbol ___GLO(92,___G__23__23_string_2d__3e_symbol)
#define ___PRM__23__23_string_2d__3e_symbol ___PRM(92,___G__23__23_string_2d__3e_symbol)
#define ___GLO__23__23_string_2d_append ___GLO(93,___G__23__23_string_2d_append)
#define ___PRM__23__23_string_2d_append ___PRM(93,___G__23__23_string_2d_append)
#define ___GLO__23__23_symbol_2d__3e_string ___GLO(94,___G__23__23_symbol_2d__3e_string)
#define ___PRM__23__23_symbol_2d__3e_string ___PRM(94,___G__23__23_symbol_2d__3e_string)
#define ___GLO_c_23_compiler_2d_internal_2d_error ___GLO(95,___G_c_23_compiler_2d_internal_2d_error)
#define ___PRM_c_23_compiler_2d_internal_2d_error ___PRM(95,___G_c_23_compiler_2d_internal_2d_error)
#define ___GLO_c_23_make_2d_counter ___GLO(96,___G_c_23_make_2d_counter)
#define ___PRM_c_23_make_2d_counter ___PRM(96,___G_c_23_make_2d_counter)
#define ___GLO_c_23_node_2d_parent ___GLO(97,___G_c_23_node_2d_parent)
#define ___PRM_c_23_node_2d_parent ___PRM(97,___G_c_23_node_2d_parent)
#define ___GLO_c_23_prc_3f_ ___GLO(98,___G_c_23_prc_3f_)
#define ___PRM_c_23_prc_3f_ ___PRM(98,___G_c_23_prc_3f_)
#define ___GLO_c_23_pt_2d_syntax_2d_error ___GLO(99,___G_c_23_pt_2d_syntax_2d_error)
#define ___PRM_c_23_pt_2d_syntax_2d_error ___PRM(99,___G_c_23_pt_2d_syntax_2d_error)
#define ___GLO_c_23_ptset_2d_empty ___GLO(100,___G_c_23_ptset_2d_empty)
#define ___PRM_c_23_ptset_2d_empty ___PRM(100,___G_c_23_ptset_2d_empty)
#define ___GLO_c_23_varset_2d_singleton ___GLO(101,___G_c_23_varset_2d_singleton)
#define ___PRM_c_23_varset_2d_singleton ___PRM(101,___G_c_23_varset_2d_singleton)
#define ___GLO_eq_3f_ ___GLO(102,___G_eq_3f_)
#define ___PRM_eq_3f_ ___PRM(102,___G_eq_3f_)
#define ___GLO_make_2d_table ___GLO(103,___G_make_2d_table)
#define ___PRM_make_2d_table ___PRM(103,___G_make_2d_table)
#define ___GLO_table_2d_for_2d_each ___GLO(104,___G_table_2d_for_2d_each)
#define ___PRM_table_2d_for_2d_each ___PRM(104,___G_table_2d_for_2d_each)
#define ___GLO_table_2d_ref ___GLO(105,___G_table_2d_ref)
#define ___PRM_table_2d_ref ___PRM(105,___G_table_2d_ref)
#define ___GLO_table_2d_set_21_ ___GLO(106,___G_table_2d_set_21_)
#define ___PRM_table_2d_set_21_ ___PRM(106,___G_table_2d_set_21_)
#define ___GLO_table_3f_ ___GLO(107,___G_table_3f_)
#define ___PRM_table_3f_ ___PRM(107,___G_table_3f_)

___DEF_SUB_STR(___X0,39UL)
               ___STR8(101,110,118,45,108,111,111,107)
               ___STR8(117,112,45,118,97,114,44,32)
               ___STR8(110,97,109,101,32,105,115,32)
               ___STR8(116,104,97,116,32,111,102,32)
               ___STR7(97,32,109,97,99,114,111)
___DEF_SUB_STR(___X1,34UL)
               ___STR8(68,117,112,108,105,99,97,116)
               ___STR8(101,32,100,101,102,105,110,105)
               ___STR8(116,105,111,110,32,111,102,32)
               ___STR8(97,32,118,97,114,105,97,98)
               ___STR2(108,101)
___DEF_SUB_STR(___X2,39UL)
               ___STR8(101,110,118,45,100,101,102,105)
               ___STR8(110,101,45,118,97,114,44,32)
               ___STR8(110,97,109,101,32,105,115,32)
               ___STR8(116,104,97,116,32,111,102,32)
               ___STR7(97,32,109,97,99,114,111)
___DEF_SUB_VEC(___X3,6UL)
               ___VEC1(___REF_SUB(4))
               ___VEC1(___REF_SUB(5))
               ___VEC1(___REF_NUL)
               ___VEC1(___REF_FIX(1))
               ___VEC1(___REF_PRC(1))
               ___VEC1(___REF_FAL)
               ___VEC0
___DEF_SUB_VEC(___X4,1UL)
               ___VEC1(___REF_SYM(0,___S___env))
               ___VEC0
___DEF_SUB_VEC(___X5,0UL)
               ___VEC0

___BEGIN_SUB
 ___DEF_SUB(___X0)
,___DEF_SUB(___X1)
,___DEF_SUB(___X2)
,___DEF_SUB(___X3)
,___DEF_SUB(___X4)
,___DEF_SUB(___X5)
___END_SUB



#undef ___MD_ALL
#define ___MD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___MR_ALL
#define ___MR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___MW_ALL
#define ___MW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3 ___W_R4
___BEGIN_M_COD
___BEGIN_M_HLBL
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0___env_23_)
___DEF_M_HLBL(___L1___env_23_)
___DEF_M_HLBL(___L2___env_23_)
___DEF_M_HLBL(___L3___env_23_)
___DEF_M_HLBL(___L4___env_23_)
___DEF_M_HLBL(___L5___env_23_)
___DEF_M_HLBL(___L6___env_23_)
___DEF_M_HLBL(___L7___env_23_)
___DEF_M_HLBL(___L8___env_23_)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_make_2d_var)
___DEF_M_HLBL(___L1_c_23_make_2d_var)
___DEF_M_HLBL(___L2_c_23_make_2d_var)
___DEF_M_HLBL(___L3_c_23_make_2d_var)
___DEF_M_HLBL(___L4_c_23_make_2d_var)
___DEF_M_HLBL(___L5_c_23_make_2d_var)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_3f_)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_name)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_bound)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_refs)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_sets)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_source)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_boxed_3f_)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_info)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_stamp)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_constant)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_clone)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_temp_3f_)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_name_2d_set_21_)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_bound_2d_set_21_)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_refs_2d_set_21_)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_sets_2d_set_21_)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_source_2d_set_21_)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_boxed_3f__2d_set_21_)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_info_2d_set_21_)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_stamp_2d_set_21_)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_constant_2d_set_21_)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_clone_2d_set_21_)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_temp_3f__2d_set_21_)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_var_2d_lexical_2d_level)
___DEF_M_HLBL(___L1_c_23_var_2d_lexical_2d_level)
___DEF_M_HLBL(___L2_c_23_var_2d_lexical_2d_level)
___DEF_M_HLBL(___L3_c_23_var_2d_lexical_2d_level)
___DEF_M_HLBL(___L4_c_23_var_2d_lexical_2d_level)
___DEF_M_HLBL(___L5_c_23_var_2d_lexical_2d_level)
___DEF_M_HLBL(___L6_c_23_var_2d_lexical_2d_level)
___DEF_M_HLBL(___L7_c_23_var_2d_lexical_2d_level)
___DEF_M_HLBL(___L8_c_23_var_2d_lexical_2d_level)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_make_2d_temp_2d_var)
___DEF_M_HLBL(___L1_c_23_make_2d_temp_2d_var)
___DEF_M_HLBL(___L2_c_23_make_2d_temp_2d_var)
___DEF_M_HLBL(___L3_c_23_make_2d_temp_2d_var)
___DEF_M_HLBL(___L4_c_23_make_2d_temp_2d_var)
___DEF_M_HLBL(___L5_c_23_make_2d_temp_2d_var)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_resize_2d_var_2d_list)
___DEF_M_HLBL(___L1_c_23_resize_2d_var_2d_list)
___DEF_M_HLBL(___L2_c_23_resize_2d_var_2d_list)
___DEF_M_HLBL(___L3_c_23_resize_2d_var_2d_list)
___DEF_M_HLBL(___L4_c_23_resize_2d_var_2d_list)
___DEF_M_HLBL(___L5_c_23_resize_2d_var_2d_list)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_frame)
___DEF_M_HLBL(___L1_c_23_env_2d_frame)
___DEF_M_HLBL(___L2_c_23_env_2d_frame)
___DEF_M_HLBL(___L3_c_23_env_2d_frame)
___DEF_M_HLBL(___L4_c_23_env_2d_frame)
___DEF_M_HLBL(___L5_c_23_env_2d_frame)
___DEF_M_HLBL(___L6_c_23_env_2d_frame)
___DEF_M_HLBL(___L7_c_23_env_2d_frame)
___DEF_M_HLBL(___L8_c_23_env_2d_frame)
___DEF_M_HLBL(___L9_c_23_env_2d_frame)
___DEF_M_HLBL(___L10_c_23_env_2d_frame)
___DEF_M_HLBL(___L11_c_23_env_2d_frame)
___DEF_M_HLBL(___L12_c_23_env_2d_frame)
___DEF_M_HLBL(___L13_c_23_env_2d_frame)
___DEF_M_HLBL(___L14_c_23_env_2d_frame)
___DEF_M_HLBL(___L15_c_23_env_2d_frame)
___DEF_M_HLBL(___L16_c_23_env_2d_frame)
___DEF_M_HLBL(___L17_c_23_env_2d_frame)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_new_2d_var_21_)
___DEF_M_HLBL(___L1_c_23_env_2d_new_2d_var_21_)
___DEF_M_HLBL(___L2_c_23_env_2d_new_2d_var_21_)
___DEF_M_HLBL(___L3_c_23_env_2d_new_2d_var_21_)
___DEF_M_HLBL(___L4_c_23_env_2d_new_2d_var_21_)
___DEF_M_HLBL(___L5_c_23_env_2d_new_2d_var_21_)
___DEF_M_HLBL(___L6_c_23_env_2d_new_2d_var_21_)
___DEF_M_HLBL(___L7_c_23_env_2d_new_2d_var_21_)
___DEF_M_HLBL(___L8_c_23_env_2d_new_2d_var_21_)
___DEF_M_HLBL(___L9_c_23_env_2d_new_2d_var_21_)
___DEF_M_HLBL(___L10_c_23_env_2d_new_2d_var_21_)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_macro)
___DEF_M_HLBL(___L1_c_23_env_2d_macro)
___DEF_M_HLBL(___L2_c_23_env_2d_macro)
___DEF_M_HLBL(___L3_c_23_env_2d_macro)
___DEF_M_HLBL(___L4_c_23_env_2d_macro)
___DEF_M_HLBL(___L5_c_23_env_2d_macro)
___DEF_M_HLBL(___L6_c_23_env_2d_macro)
___DEF_M_HLBL(___L7_c_23_env_2d_macro)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_macros_2d_set)
___DEF_M_HLBL(___L1_c_23_env_2d_macros_2d_set)
___DEF_M_HLBL(___L2_c_23_env_2d_macros_2d_set)
___DEF_M_HLBL(___L3_c_23_env_2d_macros_2d_set)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_declare)
___DEF_M_HLBL(___L1_c_23_env_2d_declare)
___DEF_M_HLBL(___L2_c_23_env_2d_declare)
___DEF_M_HLBL(___L3_c_23_env_2d_declare)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_decl_2d_set)
___DEF_M_HLBL(___L1_c_23_env_2d_decl_2d_set)
___DEF_M_HLBL(___L2_c_23_env_2d_decl_2d_set)
___DEF_M_HLBL(___L3_c_23_env_2d_decl_2d_set)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_namespace)
___DEF_M_HLBL(___L1_c_23_env_2d_namespace)
___DEF_M_HLBL(___L2_c_23_env_2d_namespace)
___DEF_M_HLBL(___L3_c_23_env_2d_namespace)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_namespace_2d_set)
___DEF_M_HLBL(___L1_c_23_env_2d_namespace_2d_set)
___DEF_M_HLBL(___L2_c_23_env_2d_namespace_2d_set)
___DEF_M_HLBL(___L3_c_23_env_2d_namespace_2d_set)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_vars_2d_ref)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_macros_2d_ref)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_decl_2d_ref)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_namespace_2d_ref)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_parent_2d_ref)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_externals_2d_ref)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_frame_2d_lookup_2d_var)
___DEF_M_HLBL(___L1_c_23_env_2d_frame_2d_lookup_2d_var)
___DEF_M_HLBL(___L2_c_23_env_2d_frame_2d_lookup_2d_var)
___DEF_M_HLBL(___L3_c_23_env_2d_frame_2d_lookup_2d_var)
___DEF_M_HLBL(___L4_c_23_env_2d_frame_2d_lookup_2d_var)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_namespace_2d_lookup)
___DEF_M_HLBL(___L1_c_23_env_2d_namespace_2d_lookup)
___DEF_M_HLBL(___L2_c_23_env_2d_namespace_2d_lookup)
___DEF_M_HLBL(___L3_c_23_env_2d_namespace_2d_lookup)
___DEF_M_HLBL(___L4_c_23_env_2d_namespace_2d_lookup)
___DEF_M_HLBL(___L5_c_23_env_2d_namespace_2d_lookup)
___DEF_M_HLBL(___L6_c_23_env_2d_namespace_2d_lookup)
___DEF_M_HLBL(___L7_c_23_env_2d_namespace_2d_lookup)
___DEF_M_HLBL(___L8_c_23_env_2d_namespace_2d_lookup)
___DEF_M_HLBL(___L9_c_23_env_2d_namespace_2d_lookup)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_M_HLBL(___L1_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_M_HLBL(___L2_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_M_HLBL(___L3_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_M_HLBL(___L4_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_M_HLBL(___L5_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_M_HLBL(___L6_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_M_HLBL(___L7_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_M_HLBL(___L8_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_M_HLBL(___L9_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_M_HLBL(___L10_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_M_HLBL(___L11_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_M_HLBL(___L12_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_M_HLBL(___L13_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_M_HLBL(___L14_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_M_HLBL(___L15_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_M_HLBL(___L16_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_macro_2d_list_2d_cached)
___DEF_M_HLBL(___L1_c_23_macro_2d_list_2d_cached)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_macro_2d_list_2d_empty)
___DEF_M_HLBL(___L1_c_23_macro_2d_list_2d_empty)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_macro_2d_list_2d_ref)
___DEF_M_HLBL(___L1_c_23_macro_2d_list_2d_ref)
___DEF_M_HLBL(___L2_c_23_macro_2d_list_2d_ref)
___DEF_M_HLBL(___L3_c_23_macro_2d_list_2d_ref)
___DEF_M_HLBL(___L4_c_23_macro_2d_list_2d_ref)
___DEF_M_HLBL(___L5_c_23_macro_2d_list_2d_ref)
___DEF_M_HLBL(___L6_c_23_macro_2d_list_2d_ref)
___DEF_M_HLBL(___L7_c_23_macro_2d_list_2d_ref)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_macro_2d_list_2d_flatten)
___DEF_M_HLBL(___L1_c_23_macro_2d_list_2d_flatten)
___DEF_M_HLBL(___L2_c_23_macro_2d_list_2d_flatten)
___DEF_M_HLBL(___L3_c_23_macro_2d_list_2d_flatten)
___DEF_M_HLBL(___L4_c_23_macro_2d_list_2d_flatten)
___DEF_M_HLBL(___L5_c_23_macro_2d_list_2d_flatten)
___DEF_M_HLBL(___L6_c_23_macro_2d_list_2d_flatten)
___DEF_M_HLBL(___L7_c_23_macro_2d_list_2d_flatten)
___DEF_M_HLBL(___L8_c_23_macro_2d_list_2d_flatten)
___DEF_M_HLBL(___L9_c_23_macro_2d_list_2d_flatten)
___DEF_M_HLBL(___L10_c_23_macro_2d_list_2d_flatten)
___DEF_M_HLBL(___L11_c_23_macro_2d_list_2d_flatten)
___DEF_M_HLBL(___L12_c_23_macro_2d_list_2d_flatten)
___DEF_M_HLBL(___L13_c_23_macro_2d_list_2d_flatten)
___DEF_M_HLBL(___L14_c_23_macro_2d_list_2d_flatten)
___DEF_M_HLBL(___L15_c_23_macro_2d_list_2d_flatten)
___DEF_M_HLBL(___L16_c_23_macro_2d_list_2d_flatten)
___DEF_M_HLBL(___L17_c_23_macro_2d_list_2d_flatten)
___DEF_M_HLBL(___L18_c_23_macro_2d_list_2d_flatten)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_macro_2d_list_2d_extend)
___DEF_M_HLBL(___L1_c_23_macro_2d_list_2d_extend)
___DEF_M_HLBL(___L2_c_23_macro_2d_list_2d_extend)
___DEF_M_HLBL(___L3_c_23_macro_2d_list_2d_extend)
___DEF_M_HLBL(___L4_c_23_macro_2d_list_2d_extend)
___DEF_M_HLBL(___L5_c_23_macro_2d_list_2d_extend)
___DEF_M_HLBL(___L6_c_23_macro_2d_list_2d_extend)
___DEF_M_HLBL(___L7_c_23_macro_2d_list_2d_extend)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_macro_2d_list_2d_prefix_2d_length)
___DEF_M_HLBL(___L1_c_23_macro_2d_list_2d_prefix_2d_length)
___DEF_M_HLBL(___L2_c_23_macro_2d_list_2d_prefix_2d_length)
___DEF_M_HLBL(___L3_c_23_macro_2d_list_2d_prefix_2d_length)
___DEF_M_HLBL(___L4_c_23_macro_2d_list_2d_prefix_2d_length)
___DEF_M_HLBL(___L5_c_23_macro_2d_list_2d_prefix_2d_length)
___DEF_M_HLBL(___L6_c_23_macro_2d_list_2d_prefix_2d_length)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_macro_2d_list_2d_suffix)
___DEF_M_HLBL(___L1_c_23_macro_2d_list_2d_suffix)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_macro_2d_list_2d_overlay_2d_prefix)
___DEF_M_HLBL(___L1_c_23_macro_2d_list_2d_overlay_2d_prefix)
___DEF_M_HLBL(___L2_c_23_macro_2d_list_2d_overlay_2d_prefix)
___DEF_M_HLBL(___L3_c_23_macro_2d_list_2d_overlay_2d_prefix)
___DEF_M_HLBL(___L4_c_23_macro_2d_list_2d_overlay_2d_prefix)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_macro_2d_list_2d_table)
___DEF_M_HLBL(___L1_c_23_macro_2d_list_2d_table)
___DEF_M_HLBL(___L2_c_23_macro_2d_list_2d_table)
___DEF_M_HLBL(___L3_c_23_macro_2d_list_2d_table)
___DEF_M_HLBL(___L4_c_23_macro_2d_list_2d_table)
___DEF_M_HLBL(___L5_c_23_macro_2d_list_2d_table)
___DEF_M_HLBL(___L6_c_23_macro_2d_list_2d_table)
___DEF_M_HLBL(___L7_c_23_macro_2d_list_2d_table)
___DEF_M_HLBL(___L8_c_23_macro_2d_list_2d_table)
___DEF_M_HLBL(___L9_c_23_macro_2d_list_2d_table)
___DEF_M_HLBL(___L10_c_23_macro_2d_list_2d_table)
___DEF_M_HLBL(___L11_c_23_macro_2d_list_2d_table)
___DEF_M_HLBL(___L12_c_23_macro_2d_list_2d_table)
___DEF_M_HLBL(___L13_c_23_macro_2d_list_2d_table)
___DEF_M_HLBL(___L14_c_23_macro_2d_list_2d_table)
___DEF_M_HLBL(___L15_c_23_macro_2d_list_2d_table)
___DEF_M_HLBL(___L16_c_23_macro_2d_list_2d_table)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_lookup)
___DEF_M_HLBL(___L1_c_23_env_2d_lookup)
___DEF_M_HLBL(___L2_c_23_env_2d_lookup)
___DEF_M_HLBL(___L3_c_23_env_2d_lookup)
___DEF_M_HLBL(___L4_c_23_env_2d_lookup)
___DEF_M_HLBL(___L5_c_23_env_2d_lookup)
___DEF_M_HLBL(___L6_c_23_env_2d_lookup)
___DEF_M_HLBL(___L7_c_23_env_2d_lookup)
___DEF_M_HLBL(___L8_c_23_env_2d_lookup)
___DEF_M_HLBL(___L9_c_23_env_2d_lookup)
___DEF_M_HLBL(___L10_c_23_env_2d_lookup)
___DEF_M_HLBL(___L11_c_23_env_2d_lookup)
___DEF_M_HLBL(___L12_c_23_env_2d_lookup)
___DEF_M_HLBL(___L13_c_23_env_2d_lookup)
___DEF_M_HLBL(___L14_c_23_env_2d_lookup)
___DEF_M_HLBL(___L15_c_23_env_2d_lookup)
___DEF_M_HLBL(___L16_c_23_env_2d_lookup)
___DEF_M_HLBL(___L17_c_23_env_2d_lookup)
___DEF_M_HLBL(___L18_c_23_env_2d_lookup)
___DEF_M_HLBL(___L19_c_23_env_2d_lookup)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_namespace_2d_valid_3f_)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_full_2d_name_3f_)
___DEF_M_HLBL(___L1_c_23_full_2d_name_3f_)
___DEF_M_HLBL(___L2_c_23_full_2d_name_3f_)
___DEF_M_HLBL(___L3_c_23_full_2d_name_3f_)
___DEF_M_HLBL(___L4_c_23_full_2d_name_3f_)
___DEF_M_HLBL(___L5_c_23_full_2d_name_3f_)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_make_2d_full_2d_name)
___DEF_M_HLBL(___L1_c_23_make_2d_full_2d_name)
___DEF_M_HLBL(___L2_c_23_make_2d_full_2d_name)
___DEF_M_HLBL(___L3_c_23_make_2d_full_2d_name)
___DEF_M_HLBL(___L4_c_23_make_2d_full_2d_name)
___DEF_M_HLBL(___L5_c_23_make_2d_full_2d_name)
___DEF_M_HLBL(___L6_c_23_make_2d_full_2d_name)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_lookup_2d_var)
___DEF_M_HLBL(___L1_c_23_env_2d_lookup_2d_var)
___DEF_M_HLBL(___L2_c_23_env_2d_lookup_2d_var)
___DEF_M_HLBL(___L3_c_23_env_2d_lookup_2d_var)
___DEF_M_HLBL(___L4_c_23_env_2d_lookup_2d_var)
___DEF_M_HLBL(___L5_c_23_env_2d_lookup_2d_var)
___DEF_M_HLBL(___L6_c_23_env_2d_lookup_2d_var)
___DEF_M_HLBL(___L7_c_23_env_2d_lookup_2d_var)
___DEF_M_HLBL(___L8_c_23_env_2d_lookup_2d_var)
___DEF_M_HLBL(___L9_c_23_env_2d_lookup_2d_var)
___DEF_M_HLBL(___L10_c_23_env_2d_lookup_2d_var)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_define_2d_var)
___DEF_M_HLBL(___L1_c_23_env_2d_define_2d_var)
___DEF_M_HLBL(___L2_c_23_env_2d_define_2d_var)
___DEF_M_HLBL(___L3_c_23_env_2d_define_2d_var)
___DEF_M_HLBL(___L4_c_23_env_2d_define_2d_var)
___DEF_M_HLBL(___L5_c_23_env_2d_define_2d_var)
___DEF_M_HLBL(___L6_c_23_env_2d_define_2d_var)
___DEF_M_HLBL(___L7_c_23_env_2d_define_2d_var)
___DEF_M_HLBL(___L8_c_23_env_2d_define_2d_var)
___DEF_M_HLBL(___L9_c_23_env_2d_define_2d_var)
___DEF_M_HLBL(___L10_c_23_env_2d_define_2d_var)
___DEF_M_HLBL(___L11_c_23_env_2d_define_2d_var)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_lookup_2d_global_2d_var)
___DEF_M_HLBL(___L1_c_23_env_2d_lookup_2d_global_2d_var)
___DEF_M_HLBL(___L2_c_23_env_2d_lookup_2d_global_2d_var)
___DEF_M_HLBL(___L3_c_23_env_2d_lookup_2d_global_2d_var)
___DEF_M_HLBL(___L4_c_23_env_2d_lookup_2d_global_2d_var)
___DEF_M_HLBL(___L5_c_23_env_2d_lookup_2d_global_2d_var)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_global_2d_variables)
___DEF_M_HLBL(___L1_c_23_env_2d_global_2d_variables)
___DEF_M_HLBL(___L2_c_23_env_2d_global_2d_variables)
___DEF_M_HLBL(___L3_c_23_env_2d_global_2d_variables)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_global_2d_env)
___DEF_M_HLBL(___L1_c_23_env_2d_global_2d_env)
___DEF_M_HLBL(___L2_c_23_env_2d_global_2d_env)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2d_lookup_2d_macro)
___DEF_M_HLBL(___L1_c_23_env_2d_lookup_2d_macro)
___DEF_M_HLBL(___L2_c_23_env_2d_lookup_2d_macro)
___DEF_M_HLBL(___L3_c_23_env_2d_lookup_2d_macro)
___DEF_M_HLBL(___L4_c_23_env_2d_lookup_2d_macro)
___DEF_M_HLBL(___L5_c_23_env_2d_lookup_2d_macro)
___DEF_M_HLBL(___L6_c_23_env_2d_lookup_2d_macro)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_define_2d_flag_2d_decl)
___DEF_M_HLBL(___L1_c_23_define_2d_flag_2d_decl)
___DEF_M_HLBL(___L2_c_23_define_2d_flag_2d_decl)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_define_2d_parameterized_2d_decl)
___DEF_M_HLBL(___L1_c_23_define_2d_parameterized_2d_decl)
___DEF_M_HLBL(___L2_c_23_define_2d_parameterized_2d_decl)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_define_2d_boolean_2d_decl)
___DEF_M_HLBL(___L1_c_23_define_2d_boolean_2d_decl)
___DEF_M_HLBL(___L2_c_23_define_2d_boolean_2d_decl)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_define_2d_namable_2d_decl)
___DEF_M_HLBL(___L1_c_23_define_2d_namable_2d_decl)
___DEF_M_HLBL(___L2_c_23_define_2d_namable_2d_decl)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_define_2d_namable_2d_boolean_2d_decl)
___DEF_M_HLBL(___L1_c_23_define_2d_namable_2d_boolean_2d_decl)
___DEF_M_HLBL(___L2_c_23_define_2d_namable_2d_boolean_2d_decl)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_flag_2d_decl)
___DEF_M_HLBL(___L1_c_23_flag_2d_decl)
___DEF_M_HLBL(___L2_c_23_flag_2d_decl)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_parameterized_2d_decl)
___DEF_M_HLBL(___L1_c_23_parameterized_2d_decl)
___DEF_M_HLBL(___L2_c_23_parameterized_2d_decl)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_boolean_2d_decl)
___DEF_M_HLBL(___L1_c_23_boolean_2d_decl)
___DEF_M_HLBL(___L2_c_23_boolean_2d_decl)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_namable_2d_decl)
___DEF_M_HLBL(___L1_c_23_namable_2d_decl)
___DEF_M_HLBL(___L2_c_23_namable_2d_decl)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_namable_2d_boolean_2d_decl)
___DEF_M_HLBL(___L1_c_23_namable_2d_boolean_2d_decl)
___DEF_M_HLBL(___L2_c_23_namable_2d_boolean_2d_decl)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_declaration_2d_value)
___DEF_M_HLBL(___L1_c_23_declaration_2d_value)
___DEF_M_HLBL(___L2_c_23_declaration_2d_value)
___DEF_M_HLBL(___L3_c_23_declaration_2d_value)
___DEF_M_HLBL(___L4_c_23_declaration_2d_value)
___DEF_M_HLBL(___L5_c_23_declaration_2d_value)
___DEF_M_HLBL(___L6_c_23_declaration_2d_value)
___DEF_M_HLBL(___L7_c_23_declaration_2d_value)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2e_begin_21_)
___DEF_M_HLBL(___L1_c_23_env_2e_begin_21_)
___DEF_M_HLBL(___L2_c_23_env_2e_begin_21_)
___DEF_M_HLBL(___L3_c_23_env_2e_begin_21_)
___DEF_M_HLBL(___L4_c_23_env_2e_begin_21_)
___DEF_M_HLBL(___L5_c_23_env_2e_begin_21_)
___DEF_M_HLBL(___L6_c_23_env_2e_begin_21_)
___DEF_M_HLBL(___L7_c_23_env_2e_begin_21_)
___DEF_M_HLBL_INTRO
___DEF_M_HLBL(___L0_c_23_env_2e_end_21_)
___END_M_HLBL

___BEGIN_M_SW

#undef ___PH_PROC
#define ___PH_PROC ___H___env_23_
#undef ___PH_LBL0
#define ___PH_LBL0 1
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(9)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0___env_23_)
___DEF_P_HLBL(___L1___env_23_)
___DEF_P_HLBL(___L2___env_23_)
___DEF_P_HLBL(___L3___env_23_)
___DEF_P_HLBL(___L4___env_23_)
___DEF_P_HLBL(___L5___env_23_)
___DEF_P_HLBL(___L6___env_23_)
___DEF_P_HLBL(___L7___env_23_)
___DEF_P_HLBL(___L8___env_23_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0___env_23_)
   ___IF_NARGS_EQ(0,___NOTHING)
   ___WRONG_NARGS(0,0,0,0)
___DEF_GLBL(___L___env_23_)
___GATE2_OPEN(___ps,"_env#",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1___env_23_)
___GATE2_ENTER(___ps,"_env#",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,5,4,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R1(___CONS(___SYM_var_2d_tag,___NUL))
   ___SET_GLO(88,___G_c_23_var_2d_tag,___R1)
   ___SET_GLO(61,___G_c_23_next_2d_var_2d_stamp,___FAL)
   ___SET_GLO(65,___G_c_23_ret_2d_var,___NUL)
   ___SET_GLO(66,___G_c_23_ret_2d_var_2d_set,___NUL)
   ___SET_GLO(3,___G_c_23_closure_2d_env_2d_var,___NUL)
   ___SET_GLO(10,___G_c_23_empty_2d_var,___NUL)
   ___SET_GLO(53,___G_c_23_make_2d_global_2d_environment,___FAL)
   ___SET_GLO(53,___G_c_23_make_2d_global_2d_environment,___LBL(7))
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(4,___KEY_test)
   ___ADJFP(4)
   ___SET_R3(___TRU)
   ___SET_R2(___KEY_weak_2d_keys)
   ___SET_R1(___PRM_eq_3f_)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___CHECK_HEAP(2,4096)
___DEF_SLBL(2,___L2___env_23_)
   ___POLL(3)
___DEF_SLBL(3,___L3___env_23_)
   ___SET_R0(___LBL(4))
   ___JUMPGLONOTSAFE(___SET_NARGS(4),103,___G_make_2d_table)
___DEF_SLBL(4,___L4___env_23_)
   ___SET_GLO(45,___G_c_23_macro_2d_list_2d_index,___R1)
___GATE2_OPEN(___ps,"_env#",5,___LBL(5),___fp);
___DEF_SLBL(5,___L5___env_23_)
___GATE2_ENTER(___ps,"_env#",5,___LBL(5),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,4,___LBL(5),&___demand_attempt)){___ps->temp1=___LBL(5);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R1(___CONS(___SYM_macro_2d_index_2d_miss,___NUL))
   ___SET_GLO(40,___G_c_23_macro_2d_index_2d_miss,___R1)
   ___SET_GLO(51,___G_c_23_macro_2d_overlay_2d_limit,___FIX(32L))
   ___SET_GLO(38,___G_c_23_flag_2d_declarations,___NUL)
   ___SET_GLO(63,___G_c_23_parameterized_2d_declarations,___NUL)
   ___SET_GLO(2,___G_c_23_boolean_2d_declarations,___NUL)
   ___SET_GLO(59,___G_c_23_namable_2d_declarations,___NUL)
   ___SET_GLO(57,___G_c_23_namable_2d_boolean_2d_declarations,___NUL)
   ___SET_R1(___VOID)
   ___ADJFP(-3)
___group_demand_commit(___ps,___LBL(5),___demand_attempt);
   ___CHECK_HEAP(6,4096)
___DEF_SLBL(6,___L6___env_23_)
   ___ADJFP(-1)
   ___JUMPRET(___STK(1))
___DEF_SLBL(7,___L7___env_23_)
   ___IF_NARGS_EQ(0,___NOTHING)
   ___WRONG_NARGS(7,0,0,0)
   ___SET_R2(___NUL)
   ___SET_R1(___FAL)
   ___POLL(8)
___DEF_SLBL(8,___L8___env_23_)
   ___JUMPINT(___SET_NARGS(2),___PRC(88),___L_c_23_env_2d_frame)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_make_2d_var
#undef ___PH_LBL0
#define ___PH_LBL0 11
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(6)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_make_2d_var)
___DEF_P_HLBL(___L1_c_23_make_2d_var)
___DEF_P_HLBL(___L2_c_23_make_2d_var)
___DEF_P_HLBL(___L3_c_23_make_2d_var)
___DEF_P_HLBL(___L4_c_23_make_2d_var)
___DEF_P_HLBL(___L5_c_23_make_2d_var)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_make_2d_var)
   ___IF_NARGS_EQ(6,___NOTHING)
   ___WRONG_NARGS(0,6,0,0)
___DEF_GLBL(___L_c_23_make_2d_var)
___GATE2_OPEN(___ps,"c#make-var",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_make_2d_var)
___GATE2_ENTER(___ps,"c#make-var",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,9,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_STK(1,___R3)
   ___ADJFP(1)
   ___ADJFP(5)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___POLL(2)
___DEF_SLBL(2,___L2_c_23_make_2d_var)
   ___SET_R0(___LBL(3))
   ___JUMPGLONOTSAFE(___SET_NARGS(0),61,___G_c_23_next_2d_var_2d_stamp)
___DEF_SLBL(3,___L3_c_23_make_2d_var)
___GATE2_OPEN(___ps,"c#make-var",4,___LBL(4),___fp);
___DEF_SLBL(4,___L4_c_23_make_2d_var)
___GATE2_ENTER(___ps,"c#make-var",4,___LBL(4),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,14,___LBL(4),&___demand_attempt)){___ps->temp1=___LBL(4);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___BEGIN_ALLOC_VECTOR(12UL)
   ___ADD_VECTOR_ELEM(0,___GLO_c_23_var_2d_tag)
   ___ADD_VECTOR_ELEM(1,___STK(-11))
   ___ADD_VECTOR_ELEM(2,___STK(-10))
   ___ADD_VECTOR_ELEM(3,___STK(-9))
   ___ADD_VECTOR_ELEM(4,___STK(-7))
   ___ADD_VECTOR_ELEM(5,___STK(-6))
   ___ADD_VECTOR_ELEM(6,___FAL)
   ___ADD_VECTOR_ELEM(7,___FAL)
   ___ADD_VECTOR_ELEM(8,___R1)
   ___ADD_VECTOR_ELEM(9,___FAL)
   ___ADD_VECTOR_ELEM(10,___FAL)
   ___ADD_VECTOR_ELEM(11,___STK(-5))
   ___END_ALLOC_VECTOR(12)
   ___SET_R1(___GET_VECTOR(12))
   ___ADJFP(-8)
___group_demand_commit(___ps,___LBL(4),___demand_attempt);
   ___CHECK_HEAP(5,4096)
___DEF_SLBL(5,___L5_c_23_make_2d_var)
   ___ADJFP(-4)
   ___JUMPRET(___STK(4))
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_3f_
#undef ___PH_LBL0
#define ___PH_LBL0 18
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1 ___D_R2
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1 ___R_R2
#undef ___PW_ALL
#define ___PW_ALL ___W_R1 ___W_R2
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_3f_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_3f_)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_var_3f_)
   ___IF(___NOT(___VECTORP(___R1)))
   ___GOTO(___L1_c_23_var_3f_)
   ___END_IF
   ___SET_R2(___VECTORLENGTH(___R1))
   ___IF(___NOT(___FIXGT(___R2,___FIX(0L))))
   ___GOTO(___L1_c_23_var_3f_)
   ___END_IF
   ___SET_R1(___VECTORREF(___R1,___FIX(0L)))
   ___SET_R1(___BOOLEAN(___EQP(___R1,___GLO_c_23_var_2d_tag)))
   ___JUMPRET(___R0)
___DEF_GLBL(___L1_c_23_var_3f_)
   ___SET_R1(___FAL)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_name
#undef ___PH_LBL0
#define ___PH_LBL0 20
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_name)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_name)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_var_2d_name)
   ___SET_R1(___VECTORREF(___R1,___FIX(1L)))
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_bound
#undef ___PH_LBL0
#define ___PH_LBL0 22
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_bound)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_bound)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_var_2d_bound)
   ___SET_R1(___VECTORREF(___R1,___FIX(2L)))
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_refs
#undef ___PH_LBL0
#define ___PH_LBL0 24
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_refs)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_refs)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_var_2d_refs)
   ___SET_R1(___VECTORREF(___R1,___FIX(3L)))
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_sets
#undef ___PH_LBL0
#define ___PH_LBL0 26
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_sets)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_sets)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_var_2d_sets)
   ___SET_R1(___VECTORREF(___R1,___FIX(4L)))
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_source
#undef ___PH_LBL0
#define ___PH_LBL0 28
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_source)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_source)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_var_2d_source)
   ___SET_R1(___VECTORREF(___R1,___FIX(5L)))
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_boxed_3f_
#undef ___PH_LBL0
#define ___PH_LBL0 30
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_boxed_3f_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_boxed_3f_)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_var_2d_boxed_3f_)
   ___SET_R1(___VECTORREF(___R1,___FIX(6L)))
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_info
#undef ___PH_LBL0
#define ___PH_LBL0 32
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_info)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_info)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_var_2d_info)
   ___SET_R1(___VECTORREF(___R1,___FIX(7L)))
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_stamp
#undef ___PH_LBL0
#define ___PH_LBL0 34
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_stamp)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_stamp)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_var_2d_stamp)
   ___SET_R1(___VECTORREF(___R1,___FIX(8L)))
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_constant
#undef ___PH_LBL0
#define ___PH_LBL0 36
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_constant)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_constant)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_var_2d_constant)
   ___SET_R1(___VECTORREF(___R1,___FIX(9L)))
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_clone
#undef ___PH_LBL0
#define ___PH_LBL0 38
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_clone)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_clone)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_var_2d_clone)
   ___SET_R1(___VECTORREF(___R1,___FIX(10L)))
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_temp_3f_
#undef ___PH_LBL0
#define ___PH_LBL0 40
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_temp_3f_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_temp_3f_)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_var_2d_temp_3f_)
   ___SET_R1(___VECTORREF(___R1,___FIX(11L)))
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_name_2d_set_21_
#undef ___PH_LBL0
#define ___PH_LBL0 42
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1 ___D_R2
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1 ___R_R2
#undef ___PW_ALL
#define ___PW_ALL
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_name_2d_set_21_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_name_2d_set_21_)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_var_2d_name_2d_set_21_)
   ___VECTORSET(___R1,___FIX(1L),___R2)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_bound_2d_set_21_
#undef ___PH_LBL0
#define ___PH_LBL0 44
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1 ___D_R2
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1 ___R_R2
#undef ___PW_ALL
#define ___PW_ALL
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_bound_2d_set_21_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_bound_2d_set_21_)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_var_2d_bound_2d_set_21_)
   ___VECTORSET(___R1,___FIX(2L),___R2)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_refs_2d_set_21_
#undef ___PH_LBL0
#define ___PH_LBL0 46
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1 ___D_R2
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1 ___R_R2
#undef ___PW_ALL
#define ___PW_ALL
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_refs_2d_set_21_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_refs_2d_set_21_)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_var_2d_refs_2d_set_21_)
   ___VECTORSET(___R1,___FIX(3L),___R2)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_sets_2d_set_21_
#undef ___PH_LBL0
#define ___PH_LBL0 48
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1 ___D_R2
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1 ___R_R2
#undef ___PW_ALL
#define ___PW_ALL
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_sets_2d_set_21_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_sets_2d_set_21_)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_var_2d_sets_2d_set_21_)
   ___VECTORSET(___R1,___FIX(4L),___R2)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_source_2d_set_21_
#undef ___PH_LBL0
#define ___PH_LBL0 50
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1 ___D_R2
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1 ___R_R2
#undef ___PW_ALL
#define ___PW_ALL
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_source_2d_set_21_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_source_2d_set_21_)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_var_2d_source_2d_set_21_)
   ___VECTORSET(___R1,___FIX(5L),___R2)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_boxed_3f__2d_set_21_
#undef ___PH_LBL0
#define ___PH_LBL0 52
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1 ___D_R2
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1 ___R_R2
#undef ___PW_ALL
#define ___PW_ALL
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_boxed_3f__2d_set_21_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_boxed_3f__2d_set_21_)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_var_2d_boxed_3f__2d_set_21_)
   ___VECTORSET(___R1,___FIX(6L),___R2)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_info_2d_set_21_
#undef ___PH_LBL0
#define ___PH_LBL0 54
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1 ___D_R2
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1 ___R_R2
#undef ___PW_ALL
#define ___PW_ALL
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_info_2d_set_21_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_info_2d_set_21_)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_var_2d_info_2d_set_21_)
   ___VECTORSET(___R1,___FIX(7L),___R2)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_stamp_2d_set_21_
#undef ___PH_LBL0
#define ___PH_LBL0 56
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1 ___D_R2
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1 ___R_R2
#undef ___PW_ALL
#define ___PW_ALL
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_stamp_2d_set_21_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_stamp_2d_set_21_)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_var_2d_stamp_2d_set_21_)
   ___VECTORSET(___R1,___FIX(8L),___R2)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_constant_2d_set_21_
#undef ___PH_LBL0
#define ___PH_LBL0 58
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1 ___D_R2
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1 ___R_R2
#undef ___PW_ALL
#define ___PW_ALL
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_constant_2d_set_21_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_constant_2d_set_21_)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_var_2d_constant_2d_set_21_)
   ___VECTORSET(___R1,___FIX(9L),___R2)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_clone_2d_set_21_
#undef ___PH_LBL0
#define ___PH_LBL0 60
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1 ___D_R2
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1 ___R_R2
#undef ___PW_ALL
#define ___PW_ALL
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_clone_2d_set_21_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_clone_2d_set_21_)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_var_2d_clone_2d_set_21_)
   ___VECTORSET(___R1,___FIX(10L),___R2)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_temp_3f__2d_set_21_
#undef ___PH_LBL0
#define ___PH_LBL0 62
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1 ___D_R2
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1 ___R_R2
#undef ___PW_ALL
#define ___PW_ALL
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_temp_3f__2d_set_21_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_temp_3f__2d_set_21_)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_var_2d_temp_3f__2d_set_21_)
   ___VECTORSET(___R1,___FIX(11L),___R2)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_var_2d_lexical_2d_level
#undef ___PH_LBL0
#define ___PH_LBL0 64
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(9)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_var_2d_lexical_2d_level)
___DEF_P_HLBL(___L1_c_23_var_2d_lexical_2d_level)
___DEF_P_HLBL(___L2_c_23_var_2d_lexical_2d_level)
___DEF_P_HLBL(___L3_c_23_var_2d_lexical_2d_level)
___DEF_P_HLBL(___L4_c_23_var_2d_lexical_2d_level)
___DEF_P_HLBL(___L5_c_23_var_2d_lexical_2d_level)
___DEF_P_HLBL(___L6_c_23_var_2d_lexical_2d_level)
___DEF_P_HLBL(___L7_c_23_var_2d_lexical_2d_level)
___DEF_P_HLBL(___L8_c_23_var_2d_lexical_2d_level)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_var_2d_lexical_2d_level)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_var_2d_lexical_2d_level)
   ___SET_R1(___VECTORREF(___R1,___FIX(2L)))
   ___IF(___EQP(___R1,___FAL))
   ___GOTO(___L16_c_23_var_2d_lexical_2d_level)
   ___END_IF
   ___IF(___EQP(___R1,___TRU))
   ___GOTO(___L16_c_23_var_2d_lexical_2d_level)
   ___END_IF
   ___SET_R2(___FIX(0L))
   ___POLL(1)
___DEF_SLBL(1,___L1_c_23_var_2d_lexical_2d_level)
   ___GOTO(___L10_c_23_var_2d_lexical_2d_level)
___DEF_SLBL(2,___L2_c_23_var_2d_lexical_2d_level)
   ___IF(___NOTFALSEP(___R1))
   ___GOTO(___L15_c_23_var_2d_lexical_2d_level)
   ___END_IF
   ___SET_R1(___FIX(0L))
___DEF_GLBL(___L9_c_23_var_2d_lexical_2d_level)
   ___SET_R2(___FIXADD(___STK(-6),___R1))
   ___SET_R0(___STK(-7))
   ___SET_R1(___STK(-5))
   ___ADJFP(-8)
   ___POLL(3)
___DEF_SLBL(3,___L3_c_23_var_2d_lexical_2d_level)
___DEF_GLBL(___L10_c_23_var_2d_lexical_2d_level)
   ___IF(___NOT(___NOTFALSEP(___R1)))
   ___GOTO(___L14_c_23_var_2d_lexical_2d_level)
   ___END_IF
___GATE2_OPEN(___ps,"c#var-lexical-level",4,___LBL(4),___fp);
___DEF_SLBL(4,___L4_c_23_var_2d_lexical_2d_level)
___GATE2_ENTER(___ps,"c#var-lexical-level",4,___LBL(4),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,8,0,___LBL(4),&___demand_attempt)){___ps->temp1=___LBL(4);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___ADJFP(5)
___group_demand_commit(___ps,___LBL(4),___demand_attempt);
   ___POLL(5)
___DEF_SLBL(5,___L5_c_23_var_2d_lexical_2d_level)
   ___SET_R0(___LBL(6))
   ___JUMPGLONOTSAFE(___SET_NARGS(1),97,___G_c_23_node_2d_parent)
___DEF_SLBL(6,___L6_c_23_var_2d_lexical_2d_level)
   ___SET_STK(-4,___R1)
   ___SET_R1(___STK(-6))
   ___SET_R0(___LBL(7))
   ___JUMPGLONOTSAFE(___SET_NARGS(1),98,___G_c_23_prc_3f_)
___DEF_SLBL(7,___L7_c_23_var_2d_lexical_2d_level)
   ___IF(___NOT(___NOTFALSEP(___R1)))
   ___GOTO(___L11_c_23_var_2d_lexical_2d_level)
   ___END_IF
   ___SET_R1(___FIX(1L))
   ___GOTO(___L12_c_23_var_2d_lexical_2d_level)
___DEF_GLBL(___L11_c_23_var_2d_lexical_2d_level)
   ___SET_R1(___FIX(0L))
___DEF_GLBL(___L12_c_23_var_2d_lexical_2d_level)
   ___SET_R1(___FIXADD(___STK(-5),___R1))
   ___IF(___NOT(___NOTFALSEP(___STK(-4))))
   ___GOTO(___L13_c_23_var_2d_lexical_2d_level)
   ___END_IF
   ___SET_STK(-6,___R1)
   ___SET_R1(___STK(-4))
   ___SET_R0(___LBL(8))
   ___JUMPGLONOTSAFE(___SET_NARGS(1),97,___G_c_23_node_2d_parent)
___DEF_SLBL(8,___L8_c_23_var_2d_lexical_2d_level)
   ___SET_STK(-5,___R1)
   ___SET_R1(___STK(-4))
   ___SET_R0(___LBL(2))
   ___JUMPGLONOTSAFE(___SET_NARGS(1),98,___G_c_23_prc_3f_)
___DEF_GLBL(___L13_c_23_var_2d_lexical_2d_level)
   ___ADJFP(-8)
   ___JUMPRET(___STK(1))
___DEF_GLBL(___L14_c_23_var_2d_lexical_2d_level)
   ___SET_R1(___R2)
   ___JUMPRET(___R0)
___DEF_GLBL(___L15_c_23_var_2d_lexical_2d_level)
   ___SET_R1(___FIX(1L))
   ___GOTO(___L9_c_23_var_2d_lexical_2d_level)
___DEF_GLBL(___L16_c_23_var_2d_lexical_2d_level)
   ___SET_R1(___FIX(0L))
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_make_2d_temp_2d_var
#undef ___PH_LBL0
#define ___PH_LBL0 74
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R2 ___W_R3 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(6)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_make_2d_temp_2d_var)
___DEF_P_HLBL(___L1_c_23_make_2d_temp_2d_var)
___DEF_P_HLBL(___L2_c_23_make_2d_temp_2d_var)
___DEF_P_HLBL(___L3_c_23_make_2d_temp_2d_var)
___DEF_P_HLBL(___L4_c_23_make_2d_temp_2d_var)
___DEF_P_HLBL(___L5_c_23_make_2d_temp_2d_var)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_make_2d_temp_2d_var)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_make_2d_temp_2d_var)
___GATE2_OPEN(___ps,"c#make-temp-var",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_make_2d_temp_2d_var)
___GATE2_ENTER(___ps,"c#make-temp-var",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,8,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_STK(1,___TRU)
   ___ADJFP(1)
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___ADJFP(5)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___POLL(2)
___DEF_SLBL(2,___L2_c_23_make_2d_temp_2d_var)
   ___SET_R0(___LBL(3))
   ___JUMPGLONOTSAFE(___SET_NARGS(0),100,___G_c_23_ptset_2d_empty)
___DEF_SLBL(3,___L3_c_23_make_2d_temp_2d_var)
   ___SET_STK(-4,___STK(-5))
   ___SET_STK(-5,___R1)
   ___SET_R0(___LBL(4))
   ___JUMPGLONOTSAFE(___SET_NARGS(0),100,___G_c_23_ptset_2d_empty)
___DEF_SLBL(4,___L4_c_23_make_2d_temp_2d_var)
   ___SET_R3(___TRU)
   ___SET_R2(___FAL)
   ___SET_R0(___STK(-4))
   ___POLL(5)
___DEF_SLBL(5,___L5_c_23_make_2d_temp_2d_var)
   ___ADJFP(-5)
   ___JUMPINT(___SET_NARGS(6),___PRC(11),___L_c_23_make_2d_var)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_resize_2d_var_2d_list
#undef ___PH_LBL0
#define ___PH_LBL0 81
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R1 ___W_R2
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(6)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_resize_2d_var_2d_list)
___DEF_P_HLBL(___L1_c_23_resize_2d_var_2d_list)
___DEF_P_HLBL(___L2_c_23_resize_2d_var_2d_list)
___DEF_P_HLBL(___L3_c_23_resize_2d_var_2d_list)
___DEF_P_HLBL(___L4_c_23_resize_2d_var_2d_list)
___DEF_P_HLBL(___L5_c_23_resize_2d_var_2d_list)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_resize_2d_var_2d_list)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_resize_2d_var_2d_list)
   ___POLL(1)
___DEF_SLBL(1,___L1_c_23_resize_2d_var_2d_list)
   ___GOTO(___L7_c_23_resize_2d_var_2d_list)
___DEF_GLBL(___L6_c_23_resize_2d_var_2d_list)
   ___IF(___FIXLT(___R2,___FIX(0L)))
   ___GOTO(___L8_c_23_resize_2d_var_2d_list)
   ___END_IF
   ___SET_R2(___FIXSUB(___R2,___FIX(1L)))
___GATE2_OPEN(___ps,"c#resize-var-list",2,___LBL(2),___fp);
___DEF_SLBL(2,___L2_c_23_resize_2d_var_2d_list)
___GATE2_ENTER(___ps,"c#resize-var-list",2,___LBL(2),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,4,___LBL(2),&___demand_attempt)){___ps->temp1=___LBL(2);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R1(___CONS(___GLO_c_23_empty_2d_var,___R1))
___group_demand_commit(___ps,___LBL(2),___demand_attempt);
   ___CHECK_HEAP(3,4096)
___DEF_SLBL(3,___L3_c_23_resize_2d_var_2d_list)
   ___POLL(4)
___DEF_SLBL(4,___L4_c_23_resize_2d_var_2d_list)
___DEF_GLBL(___L7_c_23_resize_2d_var_2d_list)
   ___IF(___NOT(___FIXEQ(___R2,___FIX(0L))))
   ___GOTO(___L6_c_23_resize_2d_var_2d_list)
   ___END_IF
   ___JUMPRET(___R0)
___DEF_GLBL(___L8_c_23_resize_2d_var_2d_list)
   ___SET_R2(___FIXADD(___R2,___FIX(1L)))
   ___SET_R1(___CDR(___R1))
   ___POLL(5)
___DEF_SLBL(5,___L5_c_23_resize_2d_var_2d_list)
   ___GOTO(___L7_c_23_resize_2d_var_2d_list)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_frame
#undef ___PH_LBL0
#define ___PH_LBL0 88
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(18)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_frame)
___DEF_P_HLBL(___L1_c_23_env_2d_frame)
___DEF_P_HLBL(___L2_c_23_env_2d_frame)
___DEF_P_HLBL(___L3_c_23_env_2d_frame)
___DEF_P_HLBL(___L4_c_23_env_2d_frame)
___DEF_P_HLBL(___L5_c_23_env_2d_frame)
___DEF_P_HLBL(___L6_c_23_env_2d_frame)
___DEF_P_HLBL(___L7_c_23_env_2d_frame)
___DEF_P_HLBL(___L8_c_23_env_2d_frame)
___DEF_P_HLBL(___L9_c_23_env_2d_frame)
___DEF_P_HLBL(___L10_c_23_env_2d_frame)
___DEF_P_HLBL(___L11_c_23_env_2d_frame)
___DEF_P_HLBL(___L12_c_23_env_2d_frame)
___DEF_P_HLBL(___L13_c_23_env_2d_frame)
___DEF_P_HLBL(___L14_c_23_env_2d_frame)
___DEF_P_HLBL(___L15_c_23_env_2d_frame)
___DEF_P_HLBL(___L16_c_23_env_2d_frame)
___DEF_P_HLBL(___L17_c_23_env_2d_frame)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_frame)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_env_2d_frame)
   ___IF(___NOT(___NOTFALSEP(___R1)))
   ___GOTO(___L23_c_23_env_2d_frame)
   ___END_IF
___GATE2_OPEN(___ps,"c#env-frame",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_env_2d_frame)
___GATE2_ENTER(___ps,"c#env-frame",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,1,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_R1(___FAL)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___GOTO(___L18_c_23_env_2d_frame)
___DEF_SLBL(2,___L2_c_23_env_2d_frame)
   ___SET_R1(___STK(-4))
   ___SET_R2(___STK(-5))
   ___SET_R0(___STK(-7))
   ___SET_STK(-7,___STK(-6))
   ___ADJFP(-7)
___DEF_GLBL(___L18_c_23_env_2d_frame)
___GATE2_OPEN(___ps,"c#env-frame",3,___LBL(3),___fp);
___DEF_SLBL(3,___L3_c_23_env_2d_frame)
___GATE2_ENTER(___ps,"c#env-frame",3,___LBL(3),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,4,___LBL(3),&___demand_attempt)){___ps->temp1=___LBL(3);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R1(___CONS(___R2,___R1))
___group_demand_commit(___ps,___LBL(3),___demand_attempt);
   ___CHECK_HEAP(4,4096)
___DEF_SLBL(4,___L4_c_23_env_2d_frame)
   ___IF(___NOT(___NOTFALSEP(___STK(0))))
   ___GOTO(___L21_c_23_env_2d_frame)
   ___END_IF
   ___SET_R2(___VECTORREF(___STK(0),___FIX(2L)))
   ___IF(___NOT(___NOTFALSEP(___STK(0))))
   ___GOTO(___L22_c_23_env_2d_frame)
   ___END_IF
___DEF_GLBL(___L19_c_23_env_2d_frame)
   ___SET_R3(___VECTORREF(___STK(0),___FIX(5L)))
___DEF_GLBL(___L20_c_23_env_2d_frame)
___GATE2_OPEN(___ps,"c#env-frame",5,___LBL(5),___fp);
___DEF_SLBL(5,___L5_c_23_env_2d_frame)
___GATE2_ENTER(___ps,"c#env-frame",5,___LBL(5),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,8,___LBL(5),&___demand_attempt)){___ps->temp1=___LBL(5);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___BEGIN_ALLOC_VECTOR(6UL)
   ___ADD_VECTOR_ELEM(0,___R1)
   ___ADD_VECTOR_ELEM(1,___NUL)
   ___ADD_VECTOR_ELEM(2,___R2)
   ___ADD_VECTOR_ELEM(3,___NUL)
   ___ADD_VECTOR_ELEM(4,___STK(0))
   ___ADD_VECTOR_ELEM(5,___R3)
   ___END_ALLOC_VECTOR(6)
   ___SET_R1(___GET_VECTOR(6))
   ___ADJFP(-1)
___group_demand_commit(___ps,___LBL(5),___demand_attempt);
   ___CHECK_HEAP(6,4096)
___DEF_SLBL(6,___L6_c_23_env_2d_frame)
   ___JUMPRET(___R0)
___DEF_GLBL(___L21_c_23_env_2d_frame)
   ___SET_R2(___NUL)
   ___IF(___NOTFALSEP(___STK(0)))
   ___GOTO(___L19_c_23_env_2d_frame)
   ___END_IF
___DEF_GLBL(___L22_c_23_env_2d_frame)
___GATE2_OPEN(___ps,"c#env-frame",7,___LBL(7),___fp);
___DEF_SLBL(7,___L7_c_23_env_2d_frame)
___GATE2_ENTER(___ps,"c#env-frame",7,___LBL(7),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,7,0,___LBL(7),&___demand_attempt)){___ps->temp1=___LBL(7);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___ADJFP(4)
___group_demand_commit(___ps,___LBL(7),___demand_attempt);
   ___POLL(8)
___DEF_SLBL(8,___L8_c_23_env_2d_frame)
   ___SET_R0(___LBL(9))
   ___JUMPGLONOTSAFE(___SET_NARGS(0),103,___G_make_2d_table)
___DEF_SLBL(9,___L9_c_23_env_2d_frame)
   ___SET_R3(___R1)
   ___SET_R2(___STK(-4))
   ___SET_R1(___STK(-5))
   ___SET_R0(___STK(-6))
   ___ADJFP(-7)
   ___GOTO(___L20_c_23_env_2d_frame)
___DEF_GLBL(___L23_c_23_env_2d_frame)
___GATE2_OPEN(___ps,"c#env-frame",10,___LBL(10),___fp);
___DEF_SLBL(10,___L10_c_23_env_2d_frame)
___GATE2_ENTER(___ps,"c#env-frame",10,___LBL(10),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,8,0,___LBL(10),&___demand_attempt)){___ps->temp1=___LBL(10);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_R2(___PRM_eq_3f_)
   ___SET_R1(___KEY_test)
   ___ADJFP(5)
___group_demand_commit(___ps,___LBL(10),___demand_attempt);
   ___POLL(11)
___DEF_SLBL(11,___L11_c_23_env_2d_frame)
   ___SET_R0(___LBL(12))
   ___JUMPGLONOTSAFE(___SET_NARGS(2),103,___G_make_2d_table)
___DEF_SLBL(12,___L12_c_23_env_2d_frame)
   ___SET_STK(-4,___R1)
   ___SET_R2(___STK(-5))
   ___SET_R0(___LBL(2))
   ___IF(___PAIRP(___R2))
   ___GOTO(___L25_c_23_env_2d_frame)
   ___END_IF
   ___GOTO(___L26_c_23_env_2d_frame)
___DEF_SLBL(13,___L13_c_23_env_2d_frame)
___DEF_GLBL(___L24_c_23_env_2d_frame)
   ___SET_R2(___CDR(___STK(-5)))
   ___SET_R1(___STK(-6))
   ___SET_R0(___STK(-7))
   ___ADJFP(-8)
   ___POLL(14)
___DEF_SLBL(14,___L14_c_23_env_2d_frame)
   ___IF(___NOT(___PAIRP(___R2)))
   ___GOTO(___L26_c_23_env_2d_frame)
   ___END_IF
___DEF_GLBL(___L25_c_23_env_2d_frame)
___GATE2_OPEN(___ps,"c#env-frame",15,___LBL(15),___fp);
___DEF_SLBL(15,___L15_c_23_env_2d_frame)
___GATE2_ENTER(___ps,"c#env-frame",15,___LBL(15),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,8,0,___LBL(15),&___demand_attempt)){___ps->temp1=___LBL(15);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R3(___CAR(___R2))
   ___SET_R4(___VECTORREF(___R3,___FIX(1L)))
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_STK(1,___R3)
   ___ADJFP(1)
   ___SET_STK(1,___R4)
   ___ADJFP(1)
   ___SET_R2(___R4)
   ___SET_R3(___FAL)
   ___ADJFP(3)
___group_demand_commit(___ps,___LBL(15),___demand_attempt);
   ___POLL(16)
___DEF_SLBL(16,___L16_c_23_env_2d_frame)
   ___SET_R0(___LBL(17))
   ___JUMPGLONOTSAFE(___SET_NARGS(3),105,___G_table_2d_ref)
___DEF_SLBL(17,___L17_c_23_env_2d_frame)
   ___IF(___NOTFALSEP(___R1))
   ___GOTO(___L24_c_23_env_2d_frame)
   ___END_IF
   ___SET_R3(___STK(-4))
   ___SET_R2(___STK(-3))
   ___SET_R1(___STK(-6))
   ___SET_R0(___LBL(13))
   ___JUMPGLONOTSAFE(___SET_NARGS(3),106,___G_table_2d_set_21_)
___DEF_GLBL(___L26_c_23_env_2d_frame)
   ___SET_R1(___VOID)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_new_2d_var_21_
#undef ___PH_LBL0
#define ___PH_LBL0 107
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(11)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_new_2d_var_21_)
___DEF_P_HLBL(___L1_c_23_env_2d_new_2d_var_21_)
___DEF_P_HLBL(___L2_c_23_env_2d_new_2d_var_21_)
___DEF_P_HLBL(___L3_c_23_env_2d_new_2d_var_21_)
___DEF_P_HLBL(___L4_c_23_env_2d_new_2d_var_21_)
___DEF_P_HLBL(___L5_c_23_env_2d_new_2d_var_21_)
___DEF_P_HLBL(___L6_c_23_env_2d_new_2d_var_21_)
___DEF_P_HLBL(___L7_c_23_env_2d_new_2d_var_21_)
___DEF_P_HLBL(___L8_c_23_env_2d_new_2d_var_21_)
___DEF_P_HLBL(___L9_c_23_env_2d_new_2d_var_21_)
___DEF_P_HLBL(___L10_c_23_env_2d_new_2d_var_21_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_new_2d_var_21_)
   ___IF_NARGS_EQ(3,___NOTHING)
   ___WRONG_NARGS(0,3,0,0)
___DEF_GLBL(___L_c_23_env_2d_new_2d_var_21_)
___GATE2_OPEN(___ps,"c#env-new-var!",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_env_2d_new_2d_var_21_)
___GATE2_ENTER(___ps,"c#env-new-var!",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,12,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R4(___VECTORREF(___R1,___FIX(4L)))
   ___SET_R4(___BOOLEAN(___FALSEP(___R4)))
   ___SET_STK(1,___BOOLEAN(___FALSEP(___R4)))
   ___ADJFP(1)
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_STK(1,___R3)
   ___ADJFP(1)
   ___SET_STK(1,___R4)
   ___ADJFP(1)
   ___ADJFP(6)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___POLL(2)
___DEF_SLBL(2,___L2_c_23_env_2d_new_2d_var_21_)
   ___SET_R0(___LBL(3))
   ___JUMPGLONOTSAFE(___SET_NARGS(0),100,___G_c_23_ptset_2d_empty)
___DEF_SLBL(3,___L3_c_23_env_2d_new_2d_var_21_)
   ___SET_STK(-5,___R1)
   ___SET_R0(___LBL(4))
   ___JUMPGLONOTSAFE(___SET_NARGS(0),100,___G_c_23_ptset_2d_empty)
___DEF_SLBL(4,___L4_c_23_env_2d_new_2d_var_21_)
   ___SET_STK(-4,___R1)
   ___SET_R0(___LBL(5))
   ___JUMPGLONOTSAFE(___SET_NARGS(0),61,___G_c_23_next_2d_var_2d_stamp)
___DEF_SLBL(5,___L5_c_23_env_2d_new_2d_var_21_)
___GATE2_OPEN(___ps,"c#env-new-var!",6,___LBL(6),___fp);
___DEF_SLBL(6,___L6_c_23_env_2d_new_2d_var_21_)
___GATE2_ENTER(___ps,"c#env-new-var!",6,___LBL(6),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,14,___LBL(6),&___demand_attempt)){___ps->temp1=___LBL(6);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___BEGIN_ALLOC_VECTOR(12UL)
   ___ADD_VECTOR_ELEM(0,___GLO_c_23_var_2d_tag)
   ___ADD_VECTOR_ELEM(1,___STK(-8))
   ___ADD_VECTOR_ELEM(2,___STK(-11))
   ___ADD_VECTOR_ELEM(3,___STK(-5))
   ___ADD_VECTOR_ELEM(4,___STK(-4))
   ___ADD_VECTOR_ELEM(5,___STK(-7))
   ___ADD_VECTOR_ELEM(6,___FAL)
   ___ADD_VECTOR_ELEM(7,___FAL)
   ___ADD_VECTOR_ELEM(8,___R1)
   ___ADD_VECTOR_ELEM(9,___FAL)
   ___ADD_VECTOR_ELEM(10,___FAL)
   ___ADD_VECTOR_ELEM(11,___FAL)
   ___END_ALLOC_VECTOR(12)
   ___SET_R1(___GET_VECTOR(12))
   ___SET_R2(___VECTORREF(___STK(-9),___FIX(0L)))
___group_demand_commit(___ps,___LBL(6),___demand_attempt);
   ___CHECK_HEAP(7,4096)
___DEF_SLBL(7,___L7_c_23_env_2d_new_2d_var_21_)
   ___IF(___NOTFALSEP(___STK(-6)))
   ___GOTO(___L12_c_23_env_2d_new_2d_var_21_)
   ___END_IF
   ___ADJFP(-4)
   ___GOTO(___L11_c_23_env_2d_new_2d_var_21_)
___DEF_SLBL(8,___L8_c_23_env_2d_new_2d_var_21_)
   ___SET_R2(___STK(-5))
   ___SET_R1(___STK(-7))
___DEF_GLBL(___L11_c_23_env_2d_new_2d_var_21_)
   ___SET_R3(___CAR(___R2))
___GATE2_OPEN(___ps,"c#env-new-var!",9,___LBL(9),___fp);
___DEF_SLBL(9,___L9_c_23_env_2d_new_2d_var_21_)
___GATE2_ENTER(___ps,"c#env-new-var!",9,___LBL(9),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,4,___LBL(9),&___demand_attempt)){___ps->temp1=___LBL(9);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R3(___CONS(___R1,___R3))
   ___SETCAR(___R2,___R3)
   ___ADJFP(-6)
___group_demand_commit(___ps,___LBL(9),___demand_attempt);
   ___CHECK_HEAP(10,4096)
___DEF_SLBL(10,___L10_c_23_env_2d_new_2d_var_21_)
   ___ADJFP(-2)
   ___JUMPRET(___STK(2))
___DEF_GLBL(___L12_c_23_env_2d_new_2d_var_21_)
   ___SET_STK(-11,___R1)
   ___SET_STK(-9,___R2)
   ___SET_R3(___R1)
   ___SET_R2(___STK(-8))
   ___SET_R1(___CDR(___STK(-9)))
   ___SET_R0(___LBL(8))
   ___ADJFP(-4)
   ___JUMPGLONOTSAFE(___SET_NARGS(3),106,___G_table_2d_set_21_)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_macro
#undef ___PH_LBL0
#define ___PH_LBL0 119
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(8)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_macro)
___DEF_P_HLBL(___L1_c_23_env_2d_macro)
___DEF_P_HLBL(___L2_c_23_env_2d_macro)
___DEF_P_HLBL(___L3_c_23_env_2d_macro)
___DEF_P_HLBL(___L4_c_23_env_2d_macro)
___DEF_P_HLBL(___L5_c_23_env_2d_macro)
___DEF_P_HLBL(___L6_c_23_env_2d_macro)
___DEF_P_HLBL(___L7_c_23_env_2d_macro)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_macro)
   ___IF_NARGS_EQ(3,___NOTHING)
   ___WRONG_NARGS(0,3,0,0)
___DEF_GLBL(___L_c_23_env_2d_macro)
___GATE2_OPEN(___ps,"c#env-macro",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_env_2d_macro)
___GATE2_ENTER(___ps,"c#env-macro",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,8,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_STK(1,___R3)
   ___ADJFP(1)
   ___SET_R1(___R2)
   ___ADJFP(4)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___POLL(2)
___DEF_SLBL(2,___L2_c_23_env_2d_macro)
   ___SET_R0(___LBL(3))
   ___JUMPINT(___SET_NARGS(1),___PRC(302),___L_c_23_full_2d_name_3f_)
___DEF_SLBL(3,___L3_c_23_env_2d_macro)
   ___IF(___NOT(___NOTFALSEP(___R1)))
   ___GOTO(___L10_c_23_env_2d_macro)
   ___END_IF
   ___SET_R1(___FAL)
   ___IF(___NOTFALSEP(___R1))
   ___GOTO(___L8_c_23_env_2d_macro)
   ___END_IF
   ___GOTO(___L9_c_23_env_2d_macro)
___DEF_SLBL(4,___L4_c_23_env_2d_macro)
   ___IF(___NOT(___NOTFALSEP(___R1)))
   ___GOTO(___L9_c_23_env_2d_macro)
   ___END_IF
___DEF_GLBL(___L8_c_23_env_2d_macro)
___GATE2_OPEN(___ps,"c#env-macro",5,___LBL(5),___fp);
___DEF_SLBL(5,___L5_c_23_env_2d_macro)
___GATE2_ENTER(___ps,"c#env-macro",5,___LBL(5),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,8,___LBL(5),&___demand_attempt)){___ps->temp1=___LBL(5);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R1(___CONS(___R1,___STK(-4)))
   ___SET_R2(___VECTORREF(___STK(-6),___FIX(1L)))
   ___SET_R2(___CONS(___R1,___R2))
   ___SET_R1(___STK(-6))
   ___SET_R0(___STK(-7))
___group_demand_commit(___ps,___LBL(5),___demand_attempt);
   ___CHECK_HEAP(6,4096)
___DEF_SLBL(6,___L6_c_23_env_2d_macro)
   ___POLL(7)
___DEF_SLBL(7,___L7_c_23_env_2d_macro)
   ___ADJFP(-8)
   ___JUMPINT(___SET_NARGS(2),___PRC(128),___L_c_23_env_2d_macros_2d_set)
___DEF_GLBL(___L9_c_23_env_2d_macro)
   ___SET_R1(___STK(-5))
   ___GOTO(___L8_c_23_env_2d_macro)
___DEF_GLBL(___L10_c_23_env_2d_macro)
   ___SET_R2(___STK(-5))
   ___SET_R1(___STK(-6))
   ___SET_R0(___LBL(4))
   ___JUMPINT(___SET_NARGS(2),___PRC(171),___L_c_23_env_2d_namespace_2d_lookup)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_macros_2d_set
#undef ___PH_LBL0
#define ___PH_LBL0 128
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R1 ___W_R3 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(4)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_macros_2d_set)
___DEF_P_HLBL(___L1_c_23_env_2d_macros_2d_set)
___DEF_P_HLBL(___L2_c_23_env_2d_macros_2d_set)
___DEF_P_HLBL(___L3_c_23_env_2d_macros_2d_set)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_macros_2d_set)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_env_2d_macros_2d_set)
___GATE2_OPEN(___ps,"c#env-macros-set",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_env_2d_macros_2d_set)
___GATE2_ENTER(___ps,"c#env-macros-set",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,2,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R3(___VECTORREF(___R1,___FIX(5L)))
   ___SET_R4(___VECTORREF(___R1,___FIX(4L)))
   ___SET_STK(1,___VECTORREF(___R1,___FIX(3L)))
   ___ADJFP(1)
   ___SET_STK(1,___VECTORREF(___R1,___FIX(2L)))
   ___ADJFP(1)
   ___SET_R1(___VECTORREF(___R1,___FIX(0L)))
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
___GATE2_OPEN(___ps,"c#env-macros-set",2,___LBL(2),___fp);
___DEF_SLBL(2,___L2_c_23_env_2d_macros_2d_set)
___GATE2_ENTER(___ps,"c#env-macros-set",2,___LBL(2),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,8,___LBL(2),&___demand_attempt)){___ps->temp1=___LBL(2);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___BEGIN_ALLOC_VECTOR(6UL)
   ___ADD_VECTOR_ELEM(0,___R1)
   ___ADD_VECTOR_ELEM(1,___R2)
   ___ADD_VECTOR_ELEM(2,___STK(0))
   ___ADD_VECTOR_ELEM(3,___STK(-1))
   ___ADD_VECTOR_ELEM(4,___R4)
   ___ADD_VECTOR_ELEM(5,___R3)
   ___END_ALLOC_VECTOR(6)
   ___SET_R1(___GET_VECTOR(6))
   ___ADJFP(-2)
___group_demand_commit(___ps,___LBL(2),___demand_attempt);
   ___CHECK_HEAP(3,4096)
___DEF_SLBL(3,___L3_c_23_env_2d_macros_2d_set)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_declare
#undef ___PH_LBL0
#define ___PH_LBL0 133
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R1 ___D_R2 ___D_R3
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R1 ___R_R2 ___R_R3
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R2 ___W_R3
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(4)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_declare)
___DEF_P_HLBL(___L1_c_23_env_2d_declare)
___DEF_P_HLBL(___L2_c_23_env_2d_declare)
___DEF_P_HLBL(___L3_c_23_env_2d_declare)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_declare)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_env_2d_declare)
   ___SET_R3(___VECTORREF(___R1,___FIX(2L)))
___GATE2_OPEN(___ps,"c#env-declare",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_env_2d_declare)
___GATE2_ENTER(___ps,"c#env-declare",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,4,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R2(___CONS(___R2,___R3))
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___CHECK_HEAP(2,4096)
___DEF_SLBL(2,___L2_c_23_env_2d_declare)
   ___POLL(3)
___DEF_SLBL(3,___L3_c_23_env_2d_declare)
   ___JUMPINT(___SET_NARGS(2),___PRC(138),___L_c_23_env_2d_decl_2d_set)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_decl_2d_set
#undef ___PH_LBL0
#define ___PH_LBL0 138
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R1 ___W_R3 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(4)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_decl_2d_set)
___DEF_P_HLBL(___L1_c_23_env_2d_decl_2d_set)
___DEF_P_HLBL(___L2_c_23_env_2d_decl_2d_set)
___DEF_P_HLBL(___L3_c_23_env_2d_decl_2d_set)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_decl_2d_set)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_env_2d_decl_2d_set)
___GATE2_OPEN(___ps,"c#env-decl-set",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_env_2d_decl_2d_set)
___GATE2_ENTER(___ps,"c#env-decl-set",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,2,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R3(___VECTORREF(___R1,___FIX(5L)))
   ___SET_R4(___VECTORREF(___R1,___FIX(4L)))
   ___SET_STK(1,___VECTORREF(___R1,___FIX(3L)))
   ___ADJFP(1)
   ___SET_STK(1,___VECTORREF(___R1,___FIX(1L)))
   ___ADJFP(1)
   ___SET_R1(___VECTORREF(___R1,___FIX(0L)))
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
___GATE2_OPEN(___ps,"c#env-decl-set",2,___LBL(2),___fp);
___DEF_SLBL(2,___L2_c_23_env_2d_decl_2d_set)
___GATE2_ENTER(___ps,"c#env-decl-set",2,___LBL(2),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,8,___LBL(2),&___demand_attempt)){___ps->temp1=___LBL(2);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___BEGIN_ALLOC_VECTOR(6UL)
   ___ADD_VECTOR_ELEM(0,___R1)
   ___ADD_VECTOR_ELEM(1,___STK(0))
   ___ADD_VECTOR_ELEM(2,___R2)
   ___ADD_VECTOR_ELEM(3,___STK(-1))
   ___ADD_VECTOR_ELEM(4,___R4)
   ___ADD_VECTOR_ELEM(5,___R3)
   ___END_ALLOC_VECTOR(6)
   ___SET_R1(___GET_VECTOR(6))
   ___ADJFP(-2)
___group_demand_commit(___ps,___LBL(2),___demand_attempt);
   ___CHECK_HEAP(3,4096)
___DEF_SLBL(3,___L3_c_23_env_2d_decl_2d_set)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_namespace
#undef ___PH_LBL0
#define ___PH_LBL0 143
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R1 ___D_R2 ___D_R3
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R1 ___R_R2 ___R_R3
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R2 ___W_R3
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(4)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_namespace)
___DEF_P_HLBL(___L1_c_23_env_2d_namespace)
___DEF_P_HLBL(___L2_c_23_env_2d_namespace)
___DEF_P_HLBL(___L3_c_23_env_2d_namespace)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_namespace)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_env_2d_namespace)
   ___SET_R3(___VECTORREF(___R1,___FIX(3L)))
___GATE2_OPEN(___ps,"c#env-namespace",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_env_2d_namespace)
___GATE2_ENTER(___ps,"c#env-namespace",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,4,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R2(___CONS(___R2,___R3))
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___CHECK_HEAP(2,4096)
___DEF_SLBL(2,___L2_c_23_env_2d_namespace)
   ___POLL(3)
___DEF_SLBL(3,___L3_c_23_env_2d_namespace)
   ___JUMPINT(___SET_NARGS(2),___PRC(148),___L_c_23_env_2d_namespace_2d_set)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_namespace_2d_set
#undef ___PH_LBL0
#define ___PH_LBL0 148
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R1 ___W_R3 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(4)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_namespace_2d_set)
___DEF_P_HLBL(___L1_c_23_env_2d_namespace_2d_set)
___DEF_P_HLBL(___L2_c_23_env_2d_namespace_2d_set)
___DEF_P_HLBL(___L3_c_23_env_2d_namespace_2d_set)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_namespace_2d_set)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_env_2d_namespace_2d_set)
___GATE2_OPEN(___ps,"c#env-namespace-set",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_env_2d_namespace_2d_set)
___GATE2_ENTER(___ps,"c#env-namespace-set",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,2,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R3(___VECTORREF(___R1,___FIX(5L)))
   ___SET_R4(___VECTORREF(___R1,___FIX(4L)))
   ___SET_STK(1,___VECTORREF(___R1,___FIX(2L)))
   ___ADJFP(1)
   ___SET_STK(1,___VECTORREF(___R1,___FIX(1L)))
   ___ADJFP(1)
   ___SET_R1(___VECTORREF(___R1,___FIX(0L)))
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
___GATE2_OPEN(___ps,"c#env-namespace-set",2,___LBL(2),___fp);
___DEF_SLBL(2,___L2_c_23_env_2d_namespace_2d_set)
___GATE2_ENTER(___ps,"c#env-namespace-set",2,___LBL(2),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,8,___LBL(2),&___demand_attempt)){___ps->temp1=___LBL(2);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___BEGIN_ALLOC_VECTOR(6UL)
   ___ADD_VECTOR_ELEM(0,___R1)
   ___ADD_VECTOR_ELEM(1,___STK(0))
   ___ADD_VECTOR_ELEM(2,___STK(-1))
   ___ADD_VECTOR_ELEM(3,___R2)
   ___ADD_VECTOR_ELEM(4,___R4)
   ___ADD_VECTOR_ELEM(5,___R3)
   ___END_ALLOC_VECTOR(6)
   ___SET_R1(___GET_VECTOR(6))
   ___ADJFP(-2)
___group_demand_commit(___ps,___LBL(2),___demand_attempt);
   ___CHECK_HEAP(3,4096)
___DEF_SLBL(3,___L3_c_23_env_2d_namespace_2d_set)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_vars_2d_ref
#undef ___PH_LBL0
#define ___PH_LBL0 153
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_vars_2d_ref)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_vars_2d_ref)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_env_2d_vars_2d_ref)
   ___SET_R1(___VECTORREF(___R1,___FIX(0L)))
   ___SET_R1(___CAR(___R1))
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_macros_2d_ref
#undef ___PH_LBL0
#define ___PH_LBL0 155
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_macros_2d_ref)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_macros_2d_ref)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_env_2d_macros_2d_ref)
   ___SET_R1(___VECTORREF(___R1,___FIX(1L)))
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_decl_2d_ref
#undef ___PH_LBL0
#define ___PH_LBL0 157
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_decl_2d_ref)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_decl_2d_ref)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_env_2d_decl_2d_ref)
   ___SET_R1(___VECTORREF(___R1,___FIX(2L)))
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_namespace_2d_ref
#undef ___PH_LBL0
#define ___PH_LBL0 159
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_namespace_2d_ref)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_namespace_2d_ref)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_env_2d_namespace_2d_ref)
   ___SET_R1(___VECTORREF(___R1,___FIX(3L)))
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_parent_2d_ref
#undef ___PH_LBL0
#define ___PH_LBL0 161
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_parent_2d_ref)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_parent_2d_ref)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_env_2d_parent_2d_ref)
   ___SET_R1(___VECTORREF(___R1,___FIX(4L)))
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_externals_2d_ref
#undef ___PH_LBL0
#define ___PH_LBL0 163
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_externals_2d_ref)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_externals_2d_ref)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_env_2d_externals_2d_ref)
   ___SET_R1(___VECTORREF(___R1,___FIX(5L)))
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_frame_2d_lookup_2d_var
#undef ___PH_LBL0
#define ___PH_LBL0 165
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R1 ___W_R2 ___W_R3 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(5)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_frame_2d_lookup_2d_var)
___DEF_P_HLBL(___L1_c_23_env_2d_frame_2d_lookup_2d_var)
___DEF_P_HLBL(___L2_c_23_env_2d_frame_2d_lookup_2d_var)
___DEF_P_HLBL(___L3_c_23_env_2d_frame_2d_lookup_2d_var)
___DEF_P_HLBL(___L4_c_23_env_2d_frame_2d_lookup_2d_var)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_frame_2d_lookup_2d_var)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_env_2d_frame_2d_lookup_2d_var)
   ___SET_R1(___VECTORREF(___R1,___FIX(0L)))
   ___SET_R3(___CDR(___R1))
   ___IF(___NOT(___NOTFALSEP(___R3)))
   ___GOTO(___L5_c_23_env_2d_frame_2d_lookup_2d_var)
   ___END_IF
   ___SET_R1(___R3)
   ___SET_R3(___FAL)
   ___POLL(1)
___DEF_SLBL(1,___L1_c_23_env_2d_frame_2d_lookup_2d_var)
   ___JUMPGLONOTSAFE(___SET_NARGS(3),105,___G_table_2d_ref)
___DEF_GLBL(___L5_c_23_env_2d_frame_2d_lookup_2d_var)
___GATE2_OPEN(___ps,"c#env-frame-lookup-var",2,___LBL(2),___fp);
___DEF_SLBL(2,___L2_c_23_env_2d_frame_2d_lookup_2d_var)
___GATE2_ENTER(___ps,"c#env-frame-lookup-var",2,___LBL(2),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,1,0,___LBL(2),&___demand_attempt)){___ps->temp1=___LBL(2);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R1(___CAR(___R1))
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_R2(___R1)
   ___SET_R1(___STK(0))
   ___ADJFP(-1)
___group_demand_commit(___ps,___LBL(2),___demand_attempt);
   ___POLL(3)
___DEF_SLBL(3,___L3_c_23_env_2d_frame_2d_lookup_2d_var)
   ___GOTO(___L7_c_23_env_2d_frame_2d_lookup_2d_var)
___DEF_GLBL(___L6_c_23_env_2d_frame_2d_lookup_2d_var)
   ___SET_R3(___CAR(___R2))
   ___SET_R4(___VECTORREF(___R3,___FIX(1L)))
   ___IF(___EQP(___R4,___R1))
   ___GOTO(___L8_c_23_env_2d_frame_2d_lookup_2d_var)
   ___END_IF
   ___SET_R2(___CDR(___R2))
   ___POLL(4)
___DEF_SLBL(4,___L4_c_23_env_2d_frame_2d_lookup_2d_var)
___DEF_GLBL(___L7_c_23_env_2d_frame_2d_lookup_2d_var)
   ___IF(___PAIRP(___R2))
   ___GOTO(___L6_c_23_env_2d_frame_2d_lookup_2d_var)
   ___END_IF
   ___SET_R1(___FAL)
   ___JUMPRET(___R0)
___DEF_GLBL(___L8_c_23_env_2d_frame_2d_lookup_2d_var)
   ___SET_R1(___R3)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_namespace_2d_lookup
#undef ___PH_LBL0
#define ___PH_LBL0 171
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(10)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_namespace_2d_lookup)
___DEF_P_HLBL(___L1_c_23_env_2d_namespace_2d_lookup)
___DEF_P_HLBL(___L2_c_23_env_2d_namespace_2d_lookup)
___DEF_P_HLBL(___L3_c_23_env_2d_namespace_2d_lookup)
___DEF_P_HLBL(___L4_c_23_env_2d_namespace_2d_lookup)
___DEF_P_HLBL(___L5_c_23_env_2d_namespace_2d_lookup)
___DEF_P_HLBL(___L6_c_23_env_2d_namespace_2d_lookup)
___DEF_P_HLBL(___L7_c_23_env_2d_namespace_2d_lookup)
___DEF_P_HLBL(___L8_c_23_env_2d_namespace_2d_lookup)
___DEF_P_HLBL(___L9_c_23_env_2d_namespace_2d_lookup)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_namespace_2d_lookup)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_env_2d_namespace_2d_lookup)
___GATE2_OPEN(___ps,"c#env-namespace-lookup",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_env_2d_namespace_2d_lookup)
___GATE2_ENTER(___ps,"c#env-namespace-lookup",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,1,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R1(___VECTORREF(___R1,___FIX(3L)))
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_R2(___R1)
   ___SET_R1(___STK(0))
   ___ADJFP(-1)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___POLL(2)
___DEF_SLBL(2,___L2_c_23_env_2d_namespace_2d_lookup)
   ___GOTO(___L10_c_23_env_2d_namespace_2d_lookup)
___DEF_SLBL(3,___L3_c_23_env_2d_namespace_2d_lookup)
   ___IF(___NOTFALSEP(___R1))
   ___GOTO(___L16_c_23_env_2d_namespace_2d_lookup)
   ___END_IF
   ___SET_R2(___CDR(___STK(-5)))
   ___SET_R1(___STK(-6))
   ___SET_R0(___STK(-7))
   ___ADJFP(-8)
   ___POLL(4)
___DEF_SLBL(4,___L4_c_23_env_2d_namespace_2d_lookup)
___DEF_GLBL(___L10_c_23_env_2d_namespace_2d_lookup)
   ___IF(___NOT(___PAIRP(___R2)))
   ___GOTO(___L14_c_23_env_2d_namespace_2d_lookup)
   ___END_IF
   ___SET_R3(___CAR(___R2))
   ___SET_R4(___CAR(___R3))
   ___SET_R3(___CDR(___R3))
   ___IF(___NOT(___NULLP(___R3)))
   ___GOTO(___L11_c_23_env_2d_namespace_2d_lookup)
   ___END_IF
   ___SET_R2(___R1)
   ___SET_R1(___R4)
   ___POLL(5)
___DEF_SLBL(5,___L5_c_23_env_2d_namespace_2d_lookup)
   ___JUMPINT(___SET_NARGS(2),___PRC(309),___L_c_23_make_2d_full_2d_name)
___DEF_GLBL(___L11_c_23_env_2d_namespace_2d_lookup)
___GATE2_OPEN(___ps,"c#env-namespace-lookup",6,___LBL(6),___fp);
___DEF_SLBL(6,___L6_c_23_env_2d_namespace_2d_lookup)
___GATE2_ENTER(___ps,"c#env-namespace-lookup",6,___LBL(6),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,8,0,___LBL(6),&___demand_attempt)){___ps->temp1=___LBL(6);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_STK(1,___R4)
   ___ADJFP(1)
   ___SET_R2(___R3)
   ___SET_R0(___LBL(3))
   ___ADJFP(4)
___group_demand_commit(___ps,___LBL(6),___demand_attempt);
   ___POLL(7)
___DEF_SLBL(7,___L7_c_23_env_2d_namespace_2d_lookup)
   ___GOTO(___L13_c_23_env_2d_namespace_2d_lookup)
___DEF_GLBL(___L12_c_23_env_2d_namespace_2d_lookup)
   ___SET_R3(___CAR(___R2))
   ___SET_R4(___CAR(___R3))
   ___IF(___EQP(___R1,___R4))
   ___GOTO(___L15_c_23_env_2d_namespace_2d_lookup)
   ___END_IF
   ___SET_R2(___CDR(___R2))
   ___POLL(8)
___DEF_SLBL(8,___L8_c_23_env_2d_namespace_2d_lookup)
___DEF_GLBL(___L13_c_23_env_2d_namespace_2d_lookup)
   ___IF(___PAIRP(___R2))
   ___GOTO(___L12_c_23_env_2d_namespace_2d_lookup)
   ___END_IF
___DEF_GLBL(___L14_c_23_env_2d_namespace_2d_lookup)
   ___SET_R1(___FAL)
   ___JUMPRET(___R0)
___DEF_GLBL(___L15_c_23_env_2d_namespace_2d_lookup)
   ___SET_R1(___R3)
   ___JUMPRET(___R0)
___DEF_GLBL(___L16_c_23_env_2d_namespace_2d_lookup)
   ___SET_R2(___CDR(___R1))
   ___SET_R1(___STK(-4))
   ___SET_R0(___STK(-7))
   ___POLL(9)
___DEF_SLBL(9,___L9_c_23_env_2d_namespace_2d_lookup)
   ___ADJFP(-8)
   ___JUMPINT(___SET_NARGS(2),___PRC(309),___L_c_23_make_2d_full_2d_name)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_namespace_2d_lookup_2d_both
#undef ___PH_LBL0
#define ___PH_LBL0 182
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(17)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_P_HLBL(___L1_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_P_HLBL(___L2_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_P_HLBL(___L3_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_P_HLBL(___L4_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_P_HLBL(___L5_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_P_HLBL(___L6_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_P_HLBL(___L7_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_P_HLBL(___L8_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_P_HLBL(___L9_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_P_HLBL(___L10_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_P_HLBL(___L11_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_P_HLBL(___L12_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_P_HLBL(___L13_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_P_HLBL(___L14_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_P_HLBL(___L15_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_P_HLBL(___L16_c_23_env_2d_namespace_2d_lookup_2d_both)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_namespace_2d_lookup_2d_both)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_env_2d_namespace_2d_lookup_2d_both)
___GATE2_OPEN(___ps,"c#env-namespace-lookup-both",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_env_2d_namespace_2d_lookup_2d_both)
___GATE2_ENTER(___ps,"c#env-namespace-lookup-both",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,1,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R1(___VECTORREF(___R1,___FIX(3L)))
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_R2(___R1)
   ___SET_R1(___STK(0))
   ___ADJFP(-1)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___POLL(2)
___DEF_SLBL(2,___L2_c_23_env_2d_namespace_2d_lookup_2d_both)
   ___GOTO(___L17_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_SLBL(3,___L3_c_23_env_2d_namespace_2d_lookup_2d_both)
   ___IF(___NOTFALSEP(___R1))
   ___GOTO(___L23_c_23_env_2d_namespace_2d_lookup_2d_both)
   ___END_IF
   ___SET_R2(___CDR(___STK(-8)))
   ___SET_R1(___STK(-9))
   ___SET_R0(___STK(-10))
   ___ADJFP(-12)
   ___POLL(4)
___DEF_SLBL(4,___L4_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_GLBL(___L17_c_23_env_2d_namespace_2d_lookup_2d_both)
   ___IF(___NOT(___PAIRP(___R2)))
   ___GOTO(___L21_c_23_env_2d_namespace_2d_lookup_2d_both)
   ___END_IF
___GATE2_OPEN(___ps,"c#env-namespace-lookup-both",5,___LBL(5),___fp);
___DEF_SLBL(5,___L5_c_23_env_2d_namespace_2d_lookup_2d_both)
___GATE2_ENTER(___ps,"c#env-namespace-lookup-both",5,___LBL(5),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,1,0,___LBL(5),&___demand_attempt)){___ps->temp1=___LBL(5);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R3(___CAR(___R2))
   ___SET_R4(___CAR(___R3))
   ___SET_STK(1,___CDR(___R3))
   ___ADJFP(1)
___group_demand_commit(___ps,___LBL(5),___demand_attempt);
   ___IF(___NOT(___NULLP(___STK(0))))
   ___GOTO(___L18_c_23_env_2d_namespace_2d_lookup_2d_both)
   ___END_IF
___GATE2_OPEN(___ps,"c#env-namespace-lookup-both",6,___LBL(6),___fp);
___DEF_SLBL(6,___L6_c_23_env_2d_namespace_2d_lookup_2d_both)
___GATE2_ENTER(___ps,"c#env-namespace-lookup-both",6,___LBL(6),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,7,0,___LBL(6),&___demand_attempt)){___ps->temp1=___LBL(6);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(0,___R0)
   ___SET_STK(1,___R3)
   ___ADJFP(1)
   ___SET_R2(___R1)
   ___SET_R1(___R4)
   ___ADJFP(6)
___group_demand_commit(___ps,___LBL(6),___demand_attempt);
   ___POLL(7)
___DEF_SLBL(7,___L7_c_23_env_2d_namespace_2d_lookup_2d_both)
   ___SET_R0(___LBL(8))
   ___JUMPINT(___SET_NARGS(2),___PRC(309),___L_c_23_make_2d_full_2d_name)
___DEF_SLBL(8,___L8_c_23_env_2d_namespace_2d_lookup_2d_both)
___GATE2_OPEN(___ps,"c#env-namespace-lookup-both",9,___LBL(9),___fp);
___DEF_SLBL(9,___L9_c_23_env_2d_namespace_2d_lookup_2d_both)
___GATE2_ENTER(___ps,"c#env-namespace-lookup-both",9,___LBL(9),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,4,___LBL(9),&___demand_attempt)){___ps->temp1=___LBL(9);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R1(___CONS(___R1,___STK(-6)))
   ___ADJFP(-7)
___group_demand_commit(___ps,___LBL(9),___demand_attempt);
   ___CHECK_HEAP(10,4096)
___DEF_SLBL(10,___L10_c_23_env_2d_namespace_2d_lookup_2d_both)
   ___ADJFP(-1)
   ___JUMPRET(___STK(1))
___DEF_GLBL(___L18_c_23_env_2d_namespace_2d_lookup_2d_both)
___GATE2_OPEN(___ps,"c#env-namespace-lookup-both",11,___LBL(11),___fp);
___DEF_SLBL(11,___L11_c_23_env_2d_namespace_2d_lookup_2d_both)
___GATE2_ENTER(___ps,"c#env-namespace-lookup-both",11,___LBL(11),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,11,0,___LBL(11),&___demand_attempt)){___ps->temp1=___LBL(11);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_STK(1,___R3)
   ___ADJFP(1)
   ___SET_STK(1,___R4)
   ___ADJFP(1)
   ___SET_R2(___STK(-5))
   ___SET_R0(___LBL(3))
   ___ADJFP(6)
___group_demand_commit(___ps,___LBL(11),___demand_attempt);
   ___POLL(12)
___DEF_SLBL(12,___L12_c_23_env_2d_namespace_2d_lookup_2d_both)
   ___GOTO(___L20_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_GLBL(___L19_c_23_env_2d_namespace_2d_lookup_2d_both)
   ___SET_R3(___CAR(___R2))
   ___SET_R4(___CAR(___R3))
   ___IF(___EQP(___R1,___R4))
   ___GOTO(___L22_c_23_env_2d_namespace_2d_lookup_2d_both)
   ___END_IF
   ___SET_R2(___CDR(___R2))
   ___POLL(13)
___DEF_SLBL(13,___L13_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_GLBL(___L20_c_23_env_2d_namespace_2d_lookup_2d_both)
   ___IF(___PAIRP(___R2))
   ___GOTO(___L19_c_23_env_2d_namespace_2d_lookup_2d_both)
   ___END_IF
___DEF_GLBL(___L21_c_23_env_2d_namespace_2d_lookup_2d_both)
   ___SET_R1(___FAL)
   ___JUMPRET(___R0)
___DEF_GLBL(___L22_c_23_env_2d_namespace_2d_lookup_2d_both)
   ___SET_R1(___R3)
   ___JUMPRET(___R0)
___DEF_GLBL(___L23_c_23_env_2d_namespace_2d_lookup_2d_both)
   ___SET_R2(___CDR(___R1))
   ___SET_R1(___STK(-6))
   ___SET_R0(___LBL(14))
   ___ADJFP(-4)
   ___JUMPINT(___SET_NARGS(2),___PRC(309),___L_c_23_make_2d_full_2d_name)
___DEF_SLBL(14,___L14_c_23_env_2d_namespace_2d_lookup_2d_both)
___GATE2_OPEN(___ps,"c#env-namespace-lookup-both",15,___LBL(15),___fp);
___DEF_SLBL(15,___L15_c_23_env_2d_namespace_2d_lookup_2d_both)
___GATE2_ENTER(___ps,"c#env-namespace-lookup-both",15,___LBL(15),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,4,___LBL(15),&___demand_attempt)){___ps->temp1=___LBL(15);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R1(___CONS(___R1,___STK(-3)))
   ___ADJFP(-6)
___group_demand_commit(___ps,___LBL(15),___demand_attempt);
   ___CHECK_HEAP(16,4096)
___DEF_SLBL(16,___L16_c_23_env_2d_namespace_2d_lookup_2d_both)
   ___ADJFP(-2)
   ___JUMPRET(___STK(2))
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_macro_2d_list_2d_cached
#undef ___PH_LBL0
#define ___PH_LBL0 200
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_FP ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_FP ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_R1 ___W_R2 ___W_R3 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(2)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_macro_2d_list_2d_cached)
___DEF_P_HLBL(___L1_c_23_macro_2d_list_2d_cached)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_macro_2d_list_2d_cached)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_macro_2d_list_2d_cached)
   ___SET_R2(___R1)
   ___SET_R3(___FAL)
   ___SET_R1(___GLO_c_23_macro_2d_list_2d_index)
   ___POLL(1)
___DEF_SLBL(1,___L1_c_23_macro_2d_list_2d_cached)
   ___JUMPGLONOTSAFE(___SET_NARGS(3),105,___G_table_2d_ref)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_macro_2d_list_2d_empty
#undef ___PH_LBL0
#define ___PH_LBL0 203
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_FP ___D_R1 ___D_R2 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_FP ___R_R1 ___R_R2 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_R1 ___W_R2 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(2)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_macro_2d_list_2d_empty)
___DEF_P_HLBL(___L1_c_23_macro_2d_list_2d_empty)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_macro_2d_list_2d_empty)
   ___IF_NARGS_EQ(0,___NOTHING)
   ___WRONG_NARGS(0,0,0,0)
___DEF_GLBL(___L_c_23_macro_2d_list_2d_empty)
   ___SET_R2(___PRM_eq_3f_)
   ___SET_R1(___KEY_test)
   ___POLL(1)
___DEF_SLBL(1,___L1_c_23_macro_2d_list_2d_empty)
   ___JUMPGLONOTSAFE(___SET_NARGS(2),103,___G_make_2d_table)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_macro_2d_list_2d_ref
#undef ___PH_LBL0
#define ___PH_LBL0 206
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(8)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_macro_2d_list_2d_ref)
___DEF_P_HLBL(___L1_c_23_macro_2d_list_2d_ref)
___DEF_P_HLBL(___L2_c_23_macro_2d_list_2d_ref)
___DEF_P_HLBL(___L3_c_23_macro_2d_list_2d_ref)
___DEF_P_HLBL(___L4_c_23_macro_2d_list_2d_ref)
___DEF_P_HLBL(___L5_c_23_macro_2d_list_2d_ref)
___DEF_P_HLBL(___L6_c_23_macro_2d_list_2d_ref)
___DEF_P_HLBL(___L7_c_23_macro_2d_list_2d_ref)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_macro_2d_list_2d_ref)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_macro_2d_list_2d_ref)
___GATE2_OPEN(___ps,"c#macro-list-ref",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_macro_2d_list_2d_ref)
___GATE2_ENTER(___ps,"c#macro-list-ref",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,1,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_R2(___R1)
   ___SET_R1(___STK(0))
   ___ADJFP(-1)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___POLL(2)
___DEF_SLBL(2,___L2_c_23_macro_2d_list_2d_ref)
   ___GOTO(___L8_c_23_macro_2d_list_2d_ref)
___DEF_SLBL(3,___L3_c_23_macro_2d_list_2d_ref)
   ___IF(___NOTFALSEP(___R1))
   ___GOTO(___L9_c_23_macro_2d_list_2d_ref)
   ___END_IF
   ___SET_R1(___VECTORREF(___STK(-5),___FIX(1L)))
   ___IF(___EQP(___R1,___STK(-6)))
   ___GOTO(___L10_c_23_macro_2d_list_2d_ref)
   ___END_IF
   ___SET_R2(___VECTORREF(___STK(-5),___FIX(3L)))
   ___SET_R1(___STK(-6))
   ___SET_R0(___STK(-7))
   ___ADJFP(-8)
   ___POLL(4)
___DEF_SLBL(4,___L4_c_23_macro_2d_list_2d_ref)
___DEF_GLBL(___L8_c_23_macro_2d_list_2d_ref)
___GATE2_OPEN(___ps,"c#macro-list-ref",5,___LBL(5),___fp);
___DEF_SLBL(5,___L5_c_23_macro_2d_list_2d_ref)
___GATE2_ENTER(___ps,"c#macro-list-ref",5,___LBL(5),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,8,0,___LBL(5),&___demand_attempt)){___ps->temp1=___LBL(5);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_R1(___R2)
   ___ADJFP(5)
___group_demand_commit(___ps,___LBL(5),___demand_attempt);
   ___POLL(6)
___DEF_SLBL(6,___L6_c_23_macro_2d_list_2d_ref)
   ___SET_R0(___LBL(3))
   ___JUMPGLONOTSAFE(___SET_NARGS(1),107,___G_table_3f_)
___DEF_GLBL(___L9_c_23_macro_2d_list_2d_ref)
   ___SET_R2(___STK(-6))
   ___SET_R1(___STK(-5))
   ___SET_R3(___GLO_c_23_macro_2d_index_2d_miss)
   ___SET_R0(___STK(-7))
   ___POLL(7)
___DEF_SLBL(7,___L7_c_23_macro_2d_list_2d_ref)
   ___ADJFP(-8)
   ___JUMPGLONOTSAFE(___SET_NARGS(3),105,___G_table_2d_ref)
___DEF_GLBL(___L10_c_23_macro_2d_list_2d_ref)
   ___SET_R1(___VECTORREF(___STK(-5),___FIX(2L)))
   ___ADJFP(-8)
   ___JUMPRET(___STK(1))
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_macro_2d_list_2d_flatten
#undef ___PH_LBL0
#define ___PH_LBL0 215
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(19)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_macro_2d_list_2d_flatten)
___DEF_P_HLBL(___L1_c_23_macro_2d_list_2d_flatten)
___DEF_P_HLBL(___L2_c_23_macro_2d_list_2d_flatten)
___DEF_P_HLBL(___L3_c_23_macro_2d_list_2d_flatten)
___DEF_P_HLBL(___L4_c_23_macro_2d_list_2d_flatten)
___DEF_P_HLBL(___L5_c_23_macro_2d_list_2d_flatten)
___DEF_P_HLBL(___L6_c_23_macro_2d_list_2d_flatten)
___DEF_P_HLBL(___L7_c_23_macro_2d_list_2d_flatten)
___DEF_P_HLBL(___L8_c_23_macro_2d_list_2d_flatten)
___DEF_P_HLBL(___L9_c_23_macro_2d_list_2d_flatten)
___DEF_P_HLBL(___L10_c_23_macro_2d_list_2d_flatten)
___DEF_P_HLBL(___L11_c_23_macro_2d_list_2d_flatten)
___DEF_P_HLBL(___L12_c_23_macro_2d_list_2d_flatten)
___DEF_P_HLBL(___L13_c_23_macro_2d_list_2d_flatten)
___DEF_P_HLBL(___L14_c_23_macro_2d_list_2d_flatten)
___DEF_P_HLBL(___L15_c_23_macro_2d_list_2d_flatten)
___DEF_P_HLBL(___L16_c_23_macro_2d_list_2d_flatten)
___DEF_P_HLBL(___L17_c_23_macro_2d_list_2d_flatten)
___DEF_P_HLBL(___L18_c_23_macro_2d_list_2d_flatten)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_macro_2d_list_2d_flatten)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_macro_2d_list_2d_flatten)
___GATE2_OPEN(___ps,"c#macro-list-flatten",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_macro_2d_list_2d_flatten)
___GATE2_ENTER(___ps,"c#macro-list-flatten",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,8,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___ADJFP(6)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___POLL(2)
___DEF_SLBL(2,___L2_c_23_macro_2d_list_2d_flatten)
   ___SET_R0(___LBL(3))
   ___JUMPINT(___SET_NARGS(0),___PRC(203),___L_c_23_macro_2d_list_2d_empty)
___DEF_SLBL(3,___L3_c_23_macro_2d_list_2d_flatten)
   ___SET_STK(-5,___R1)
   ___SET_R2(___STK(-6))
   ___SET_R0(___LBL(18))
   ___GOTO(___L20_c_23_macro_2d_list_2d_flatten)
___DEF_SLBL(4,___L4_c_23_macro_2d_list_2d_flatten)
___DEF_GLBL(___L19_c_23_macro_2d_list_2d_flatten)
   ___SET_R2(___VECTORREF(___STK(-5),___FIX(3L)))
   ___SET_R1(___STK(-6))
   ___SET_R0(___STK(-7))
   ___ADJFP(-8)
   ___POLL(5)
___DEF_SLBL(5,___L5_c_23_macro_2d_list_2d_flatten)
___DEF_GLBL(___L20_c_23_macro_2d_list_2d_flatten)
___GATE2_OPEN(___ps,"c#macro-list-flatten",6,___LBL(6),___fp);
___DEF_SLBL(6,___L6_c_23_macro_2d_list_2d_flatten)
___GATE2_ENTER(___ps,"c#macro-list-flatten",6,___LBL(6),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,8,0,___LBL(6),&___demand_attempt)){___ps->temp1=___LBL(6);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_R1(___R2)
   ___ADJFP(5)
___group_demand_commit(___ps,___LBL(6),___demand_attempt);
   ___POLL(7)
___DEF_SLBL(7,___L7_c_23_macro_2d_list_2d_flatten)
   ___SET_R0(___LBL(8))
   ___JUMPGLONOTSAFE(___SET_NARGS(1),107,___G_table_3f_)
___DEF_SLBL(8,___L8_c_23_macro_2d_list_2d_flatten)
   ___IF(___NOT(___NOTFALSEP(___R1)))
   ___GOTO(___L22_c_23_macro_2d_list_2d_flatten)
   ___END_IF
___GATE2_OPEN(___ps,"c#macro-list-flatten",9,___LBL(9),___fp);
___DEF_SLBL(9,___L9_c_23_macro_2d_list_2d_flatten)
___GATE2_ENTER(___ps,"c#macro-list-flatten",9,___LBL(9),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,4,___LBL(9),&___demand_attempt)){___ps->temp1=___LBL(9);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(-4,___ALLOC_CLO(1UL))
   ___BEGIN_SETUP_CLO(1,___STK(-4),12)
   ___ADD_CLO_ELEM(0,___STK(-6))
   ___END_SETUP_CLO(1)
   ___SET_R1(___STK(-4))
   ___SET_R2(___STK(-5))
   ___SET_R0(___STK(-7))
   ___ADJFP(-4)
___group_demand_commit(___ps,___LBL(9),___demand_attempt);
   ___CHECK_HEAP(10,4096)
___DEF_SLBL(10,___L10_c_23_macro_2d_list_2d_flatten)
   ___POLL(11)
___DEF_SLBL(11,___L11_c_23_macro_2d_list_2d_flatten)
   ___ADJFP(-4)
   ___JUMPGLONOTSAFE(___SET_NARGS(2),104,___G_table_2d_for_2d_each)
___DEF_SLBL(12,___L12_c_23_macro_2d_list_2d_flatten)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(12,2,0,0)
___GATE2_OPEN(___ps,"c#macro-list-flatten",13,___LBL(13),___fp);
___DEF_SLBL(13,___L13_c_23_macro_2d_list_2d_flatten)
___GATE2_ENTER(___ps,"c#macro-list-flatten",13,___LBL(13),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,8,0,___LBL(13),&___demand_attempt)){___ps->temp1=___LBL(13);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_STK(1,___R4)
   ___ADJFP(1)
   ___SET_R2(___R1)
   ___SET_R1(___CLO(___R4,1))
   ___SET_R3(___GLO_c_23_macro_2d_index_2d_miss)
   ___ADJFP(4)
___group_demand_commit(___ps,___LBL(13),___demand_attempt);
   ___POLL(14)
___DEF_SLBL(14,___L14_c_23_macro_2d_list_2d_flatten)
   ___SET_R0(___LBL(15))
   ___JUMPGLONOTSAFE(___SET_NARGS(3),105,___G_table_2d_ref)
___DEF_SLBL(15,___L15_c_23_macro_2d_list_2d_flatten)
   ___IF(___NOT(___EQP(___R1,___GLO_c_23_macro_2d_index_2d_miss)))
   ___GOTO(___L21_c_23_macro_2d_list_2d_flatten)
   ___END_IF
   ___SET_R3(___STK(-5))
   ___SET_R2(___STK(-6))
   ___SET_R1(___CLO(___STK(-4),1))
   ___SET_R0(___STK(-7))
   ___POLL(16)
___DEF_SLBL(16,___L16_c_23_macro_2d_list_2d_flatten)
   ___ADJFP(-8)
   ___JUMPGLONOTSAFE(___SET_NARGS(3),106,___G_table_2d_set_21_)
___DEF_GLBL(___L21_c_23_macro_2d_list_2d_flatten)
   ___SET_R1(___VOID)
   ___ADJFP(-8)
   ___JUMPRET(___STK(1))
___DEF_GLBL(___L22_c_23_macro_2d_list_2d_flatten)
   ___SET_R1(___VECTORREF(___STK(-5),___FIX(1L)))
   ___SET_STK(-4,___R1)
   ___SET_R2(___R1)
   ___SET_R1(___STK(-6))
   ___SET_R3(___GLO_c_23_macro_2d_index_2d_miss)
   ___SET_R0(___LBL(17))
   ___JUMPGLONOTSAFE(___SET_NARGS(3),105,___G_table_2d_ref)
___DEF_SLBL(17,___L17_c_23_macro_2d_list_2d_flatten)
   ___IF(___NOT(___EQP(___R1,___GLO_c_23_macro_2d_index_2d_miss)))
   ___GOTO(___L19_c_23_macro_2d_list_2d_flatten)
   ___END_IF
   ___SET_R3(___VECTORREF(___STK(-5),___FIX(2L)))
   ___SET_R2(___STK(-4))
   ___SET_R1(___STK(-6))
   ___SET_R0(___LBL(4))
   ___JUMPGLONOTSAFE(___SET_NARGS(3),106,___G_table_2d_set_21_)
___DEF_SLBL(18,___L18_c_23_macro_2d_list_2d_flatten)
   ___SET_R1(___STK(-5))
   ___ADJFP(-8)
   ___JUMPRET(___STK(1))
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_macro_2d_list_2d_extend
#undef ___PH_LBL0
#define ___PH_LBL0 235
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(8)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_macro_2d_list_2d_extend)
___DEF_P_HLBL(___L1_c_23_macro_2d_list_2d_extend)
___DEF_P_HLBL(___L2_c_23_macro_2d_list_2d_extend)
___DEF_P_HLBL(___L3_c_23_macro_2d_list_2d_extend)
___DEF_P_HLBL(___L4_c_23_macro_2d_list_2d_extend)
___DEF_P_HLBL(___L5_c_23_macro_2d_list_2d_extend)
___DEF_P_HLBL(___L6_c_23_macro_2d_list_2d_extend)
___DEF_P_HLBL(___L7_c_23_macro_2d_list_2d_extend)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_macro_2d_list_2d_extend)
   ___IF_NARGS_EQ(3,___NOTHING)
   ___WRONG_NARGS(0,3,0,0)
___DEF_GLBL(___L_c_23_macro_2d_list_2d_extend)
___GATE2_OPEN(___ps,"c#macro-list-extend",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_macro_2d_list_2d_extend)
___GATE2_ENTER(___ps,"c#macro-list-extend",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,8,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_STK(1,___R3)
   ___ADJFP(1)
   ___SET_R1(___R3)
   ___ADJFP(4)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___POLL(2)
___DEF_SLBL(2,___L2_c_23_macro_2d_list_2d_extend)
   ___SET_R0(___LBL(3))
   ___JUMPGLONOTSAFE(___SET_NARGS(1),107,___G_table_3f_)
___DEF_SLBL(3,___L3_c_23_macro_2d_list_2d_extend)
   ___IF(___NOT(___NOTFALSEP(___R1)))
   ___GOTO(___L8_c_23_macro_2d_list_2d_extend)
   ___END_IF
   ___SET_R1(___FIX(1L))
   ___IF(___FIXGT(___R1,___FIX(32L)))
   ___GOTO(___L9_c_23_macro_2d_list_2d_extend)
   ___END_IF
   ___GOTO(___L10_c_23_macro_2d_list_2d_extend)
___DEF_GLBL(___L8_c_23_macro_2d_list_2d_extend)
   ___SET_R1(___VECTORREF(___STK(-4),___FIX(4L)))
   ___SET_R1(___FIXADD(___FIX(1L),___R1))
   ___IF(___NOT(___FIXGT(___R1,___FIX(32L))))
   ___GOTO(___L10_c_23_macro_2d_list_2d_extend)
   ___END_IF
___DEF_GLBL(___L9_c_23_macro_2d_list_2d_extend)
   ___SET_R1(___STK(-4))
   ___SET_R0(___LBL(4))
   ___JUMPINT(___SET_NARGS(1),___PRC(215),___L_c_23_macro_2d_list_2d_flatten)
___DEF_SLBL(4,___L4_c_23_macro_2d_list_2d_extend)
   ___SET_STK(-4,___R1)
   ___SET_R3(___STK(-5))
   ___SET_R2(___STK(-6))
   ___SET_R0(___LBL(5))
   ___JUMPGLONOTSAFE(___SET_NARGS(3),106,___G_table_2d_set_21_)
___DEF_SLBL(5,___L5_c_23_macro_2d_list_2d_extend)
   ___SET_R1(___STK(-4))
   ___ADJFP(-8)
   ___JUMPRET(___STK(1))
___DEF_GLBL(___L10_c_23_macro_2d_list_2d_extend)
___GATE2_OPEN(___ps,"c#macro-list-extend",6,___LBL(6),___fp);
___DEF_SLBL(6,___L6_c_23_macro_2d_list_2d_extend)
___GATE2_ENTER(___ps,"c#macro-list-extend",6,___LBL(6),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,7,___LBL(6),&___demand_attempt)){___ps->temp1=___LBL(6);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___BEGIN_ALLOC_VECTOR(5UL)
   ___ADD_VECTOR_ELEM(0,___SYM_macro_2d_overlay)
   ___ADD_VECTOR_ELEM(1,___STK(-6))
   ___ADD_VECTOR_ELEM(2,___STK(-5))
   ___ADD_VECTOR_ELEM(3,___STK(-4))
   ___ADD_VECTOR_ELEM(4,___R1)
   ___END_ALLOC_VECTOR(5)
   ___SET_R1(___GET_VECTOR(5))
   ___ADJFP(-7)
___group_demand_commit(___ps,___LBL(6),___demand_attempt);
   ___CHECK_HEAP(7,4096)
___DEF_SLBL(7,___L7_c_23_macro_2d_list_2d_extend)
   ___ADJFP(-1)
   ___JUMPRET(___STK(1))
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_macro_2d_list_2d_prefix_2d_length
#undef ___PH_LBL0
#define ___PH_LBL0 244
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(7)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_macro_2d_list_2d_prefix_2d_length)
___DEF_P_HLBL(___L1_c_23_macro_2d_list_2d_prefix_2d_length)
___DEF_P_HLBL(___L2_c_23_macro_2d_list_2d_prefix_2d_length)
___DEF_P_HLBL(___L3_c_23_macro_2d_list_2d_prefix_2d_length)
___DEF_P_HLBL(___L4_c_23_macro_2d_list_2d_prefix_2d_length)
___DEF_P_HLBL(___L5_c_23_macro_2d_list_2d_prefix_2d_length)
___DEF_P_HLBL(___L6_c_23_macro_2d_list_2d_prefix_2d_length)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_macro_2d_list_2d_prefix_2d_length)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_macro_2d_list_2d_prefix_2d_length)
___GATE2_OPEN(___ps,"c#macro-list-prefix-length",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_macro_2d_list_2d_prefix_2d_length)
___GATE2_ENTER(___ps,"c#macro-list-prefix-length",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,1,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_R2(___R1)
   ___SET_R1(___STK(0))
   ___SET_R3(___FIX(0L))
   ___ADJFP(-1)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___POLL(2)
___DEF_SLBL(2,___L2_c_23_macro_2d_list_2d_prefix_2d_length)
   ___GOTO(___L7_c_23_macro_2d_list_2d_prefix_2d_length)
___DEF_SLBL(3,___L3_c_23_macro_2d_list_2d_prefix_2d_length)
   ___IF(___NOTFALSEP(___R1))
   ___GOTO(___L8_c_23_macro_2d_list_2d_prefix_2d_length)
   ___END_IF
   ___SET_R3(___FIXADD(___STK(-4),___FIX(1L)))
   ___SET_R2(___CDR(___STK(-5)))
   ___SET_R1(___STK(-6))
   ___SET_R0(___STK(-7))
   ___ADJFP(-8)
   ___POLL(4)
___DEF_SLBL(4,___L4_c_23_macro_2d_list_2d_prefix_2d_length)
___DEF_GLBL(___L7_c_23_macro_2d_list_2d_prefix_2d_length)
   ___IF(___FIXGE(___R3,___R1))
   ___GOTO(___L9_c_23_macro_2d_list_2d_prefix_2d_length)
   ___END_IF
   ___IF(___NOT(___PAIRP(___R2)))
   ___GOTO(___L9_c_23_macro_2d_list_2d_prefix_2d_length)
   ___END_IF
___GATE2_OPEN(___ps,"c#macro-list-prefix-length",5,___LBL(5),___fp);
___DEF_SLBL(5,___L5_c_23_macro_2d_list_2d_prefix_2d_length)
___GATE2_ENTER(___ps,"c#macro-list-prefix-length",5,___LBL(5),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,8,0,___LBL(5),&___demand_attempt)){___ps->temp1=___LBL(5);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_STK(1,___R3)
   ___ADJFP(1)
   ___SET_R1(___R2)
   ___ADJFP(4)
___group_demand_commit(___ps,___LBL(5),___demand_attempt);
   ___POLL(6)
___DEF_SLBL(6,___L6_c_23_macro_2d_list_2d_prefix_2d_length)
   ___SET_R0(___LBL(3))
   ___JUMPINT(___SET_NARGS(1),___PRC(200),___L_c_23_macro_2d_list_2d_cached)
___DEF_GLBL(___L8_c_23_macro_2d_list_2d_prefix_2d_length)
   ___SET_R3(___STK(-4))
   ___SET_R0(___STK(-7))
   ___ADJFP(-8)
___DEF_GLBL(___L9_c_23_macro_2d_list_2d_prefix_2d_length)
   ___SET_R1(___R3)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_macro_2d_list_2d_suffix
#undef ___PH_LBL0
#define ___PH_LBL0 252
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_FP ___D_R0 ___D_R1 ___D_R2
#undef ___PR_ALL
#define ___PR_ALL ___R_FP ___R_R0 ___R_R1 ___R_R2
#undef ___PW_ALL
#define ___PW_ALL ___W_R1 ___W_R2
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(2)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_macro_2d_list_2d_suffix)
___DEF_P_HLBL(___L1_c_23_macro_2d_list_2d_suffix)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_macro_2d_list_2d_suffix)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_macro_2d_list_2d_suffix)
   ___IF(___FIXEQ(___R2,___FIX(0L)))
   ___GOTO(___L4_c_23_macro_2d_list_2d_suffix)
   ___END_IF
   ___GOTO(___L3_c_23_macro_2d_list_2d_suffix)
___DEF_GLBL(___L2_c_23_macro_2d_list_2d_suffix)
   ___IF(___FIXEQ(___R2,___FIX(0L)))
   ___GOTO(___L4_c_23_macro_2d_list_2d_suffix)
   ___END_IF
___DEF_GLBL(___L3_c_23_macro_2d_list_2d_suffix)
   ___SET_R2(___FIXSUB(___R2,___FIX(1L)))
   ___SET_R1(___CDR(___R1))
   ___POLL(1)
___DEF_SLBL(1,___L1_c_23_macro_2d_list_2d_suffix)
   ___GOTO(___L2_c_23_macro_2d_list_2d_suffix)
___DEF_GLBL(___L4_c_23_macro_2d_list_2d_suffix)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_macro_2d_list_2d_overlay_2d_prefix
#undef ___PH_LBL0
#define ___PH_LBL0 255
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(5)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_macro_2d_list_2d_overlay_2d_prefix)
___DEF_P_HLBL(___L1_c_23_macro_2d_list_2d_overlay_2d_prefix)
___DEF_P_HLBL(___L2_c_23_macro_2d_list_2d_overlay_2d_prefix)
___DEF_P_HLBL(___L3_c_23_macro_2d_list_2d_overlay_2d_prefix)
___DEF_P_HLBL(___L4_c_23_macro_2d_list_2d_overlay_2d_prefix)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_macro_2d_list_2d_overlay_2d_prefix)
   ___IF_NARGS_EQ(3,___NOTHING)
   ___WRONG_NARGS(0,3,0,0)
___DEF_GLBL(___L_c_23_macro_2d_list_2d_overlay_2d_prefix)
   ___IF(___FIXEQ(___R3,___FIX(0L)))
   ___GOTO(___L7_c_23_macro_2d_list_2d_overlay_2d_prefix)
   ___END_IF
   ___GOTO(___L6_c_23_macro_2d_list_2d_overlay_2d_prefix)
___DEF_GLBL(___L5_c_23_macro_2d_list_2d_overlay_2d_prefix)
   ___IF(___FIXEQ(___R3,___FIX(0L)))
   ___GOTO(___L7_c_23_macro_2d_list_2d_overlay_2d_prefix)
   ___END_IF
___DEF_GLBL(___L6_c_23_macro_2d_list_2d_overlay_2d_prefix)
___GATE2_OPEN(___ps,"c#macro-list-overlay-prefix",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_macro_2d_list_2d_overlay_2d_prefix)
___GATE2_ENTER(___ps,"c#macro-list-overlay-prefix",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,8,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_R3(___FIXSUB(___R3,___FIX(1L)))
   ___SET_R1(___CDR(___R1))
   ___SET_R0(___LBL(3))
   ___ADJFP(6)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___POLL(2)
___DEF_SLBL(2,___L2_c_23_macro_2d_list_2d_overlay_2d_prefix)
   ___GOTO(___L5_c_23_macro_2d_list_2d_overlay_2d_prefix)
___DEF_SLBL(3,___L3_c_23_macro_2d_list_2d_overlay_2d_prefix)
   ___SET_R2(___CAR(___STK(-6)))
   ___SET_R3(___R1)
   ___SET_R1(___CDR(___R2))
   ___SET_STK(-6,___R2)
   ___SET_R2(___R1)
   ___SET_R1(___CAR(___STK(-6)))
   ___SET_R0(___STK(-7))
   ___POLL(4)
___DEF_SLBL(4,___L4_c_23_macro_2d_list_2d_overlay_2d_prefix)
   ___ADJFP(-8)
   ___JUMPINT(___SET_NARGS(3),___PRC(235),___L_c_23_macro_2d_list_2d_extend)
___DEF_GLBL(___L7_c_23_macro_2d_list_2d_overlay_2d_prefix)
   ___SET_R1(___R2)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_macro_2d_list_2d_table
#undef ___PH_LBL0
#define ___PH_LBL0 261
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(17)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_macro_2d_list_2d_table)
___DEF_P_HLBL(___L1_c_23_macro_2d_list_2d_table)
___DEF_P_HLBL(___L2_c_23_macro_2d_list_2d_table)
___DEF_P_HLBL(___L3_c_23_macro_2d_list_2d_table)
___DEF_P_HLBL(___L4_c_23_macro_2d_list_2d_table)
___DEF_P_HLBL(___L5_c_23_macro_2d_list_2d_table)
___DEF_P_HLBL(___L6_c_23_macro_2d_list_2d_table)
___DEF_P_HLBL(___L7_c_23_macro_2d_list_2d_table)
___DEF_P_HLBL(___L8_c_23_macro_2d_list_2d_table)
___DEF_P_HLBL(___L9_c_23_macro_2d_list_2d_table)
___DEF_P_HLBL(___L10_c_23_macro_2d_list_2d_table)
___DEF_P_HLBL(___L11_c_23_macro_2d_list_2d_table)
___DEF_P_HLBL(___L12_c_23_macro_2d_list_2d_table)
___DEF_P_HLBL(___L13_c_23_macro_2d_list_2d_table)
___DEF_P_HLBL(___L14_c_23_macro_2d_list_2d_table)
___DEF_P_HLBL(___L15_c_23_macro_2d_list_2d_table)
___DEF_P_HLBL(___L16_c_23_macro_2d_list_2d_table)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_macro_2d_list_2d_table)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_macro_2d_list_2d_table)
___GATE2_OPEN(___ps,"c#macro-list-table",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_macro_2d_list_2d_table)
___GATE2_ENTER(___ps,"c#macro-list-table",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,8,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_R2(___R1)
   ___SET_R3(___FAL)
   ___SET_R1(___GLO_c_23_macro_2d_list_2d_index)
   ___ADJFP(6)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___POLL(2)
___DEF_SLBL(2,___L2_c_23_macro_2d_list_2d_table)
   ___SET_R0(___LBL(3))
   ___JUMPGLONOTSAFE(___SET_NARGS(3),105,___G_table_2d_ref)
___DEF_SLBL(3,___L3_c_23_macro_2d_list_2d_table)
   ___IF(___NOTFALSEP(___R1))
   ___GOTO(___L23_c_23_macro_2d_list_2d_table)
   ___END_IF
   ___SET_R1(___STK(-6))
   ___SET_R2(___FIX(32L))
   ___SET_R0(___LBL(4))
   ___JUMPINT(___SET_NARGS(2),___PRC(244),___L_c_23_macro_2d_list_2d_prefix_2d_length)
___DEF_SLBL(4,___L4_c_23_macro_2d_list_2d_table)
   ___IF(___NOT(___FIXGT(___R1,___FIX(0L))))
   ___GOTO(___L19_c_23_macro_2d_list_2d_table)
   ___END_IF
   ___IF(___NOT(___FIXLT(___R1,___FIX(32L))))
   ___GOTO(___L19_c_23_macro_2d_list_2d_table)
   ___END_IF
   ___SET_STK(-5,___R1)
   ___SET_R2(___R1)
   ___SET_R1(___STK(-6))
   ___SET_R0(___LBL(5))
   ___JUMPINT(___SET_NARGS(2),___PRC(252),___L_c_23_macro_2d_list_2d_suffix)
___DEF_SLBL(5,___L5_c_23_macro_2d_list_2d_table)
   ___SET_R0(___LBL(6))
   ___JUMPINT(___SET_NARGS(1),___PRC(200),___L_c_23_macro_2d_list_2d_cached)
___DEF_SLBL(6,___L6_c_23_macro_2d_list_2d_table)
   ___IF(___NOTFALSEP(___R1))
   ___GOTO(___L17_c_23_macro_2d_list_2d_table)
   ___END_IF
   ___GOTO(___L18_c_23_macro_2d_list_2d_table)
___DEF_SLBL(7,___L7_c_23_macro_2d_list_2d_table)
___DEF_GLBL(___L17_c_23_macro_2d_list_2d_table)
   ___SET_R3(___STK(-5))
   ___SET_R2(___R1)
   ___SET_R1(___STK(-6))
   ___SET_R0(___LBL(8))
   ___JUMPINT(___SET_NARGS(3),___PRC(255),___L_c_23_macro_2d_list_2d_overlay_2d_prefix)
___DEF_SLBL(8,___L8_c_23_macro_2d_list_2d_table)
   ___SET_STK(-5,___R1)
   ___SET_R3(___R1)
   ___SET_R2(___STK(-6))
   ___SET_R1(___GLO_c_23_macro_2d_list_2d_index)
   ___SET_R0(___LBL(9))
   ___JUMPGLONOTSAFE(___SET_NARGS(3),106,___G_table_2d_set_21_)
___DEF_SLBL(9,___L9_c_23_macro_2d_list_2d_table)
   ___SET_R1(___STK(-5))
   ___ADJFP(-8)
   ___JUMPRET(___STK(1))
___DEF_GLBL(___L18_c_23_macro_2d_list_2d_table)
   ___SET_R0(___LBL(7))
   ___JUMPINT(___SET_NARGS(0),___PRC(203),___L_c_23_macro_2d_list_2d_empty)
___DEF_GLBL(___L19_c_23_macro_2d_list_2d_table)
   ___SET_R2(___PRM_eq_3f_)
   ___SET_R1(___KEY_test)
   ___SET_R0(___LBL(10))
   ___JUMPGLONOTSAFE(___SET_NARGS(2),103,___G_make_2d_table)
___DEF_SLBL(10,___L10_c_23_macro_2d_list_2d_table)
   ___SET_STK(-5,___R1)
   ___SET_R2(___STK(-6))
   ___SET_R0(___LBL(16))
   ___IF(___PAIRP(___R2))
   ___GOTO(___L21_c_23_macro_2d_list_2d_table)
   ___END_IF
   ___GOTO(___L22_c_23_macro_2d_list_2d_table)
___DEF_SLBL(11,___L11_c_23_macro_2d_list_2d_table)
___DEF_GLBL(___L20_c_23_macro_2d_list_2d_table)
   ___SET_R2(___CDR(___STK(-5)))
   ___SET_R1(___STK(-6))
   ___SET_R0(___STK(-7))
   ___ADJFP(-8)
   ___POLL(12)
___DEF_SLBL(12,___L12_c_23_macro_2d_list_2d_table)
   ___IF(___NOT(___PAIRP(___R2)))
   ___GOTO(___L22_c_23_macro_2d_list_2d_table)
   ___END_IF
___DEF_GLBL(___L21_c_23_macro_2d_list_2d_table)
___GATE2_OPEN(___ps,"c#macro-list-table",13,___LBL(13),___fp);
___DEF_SLBL(13,___L13_c_23_macro_2d_list_2d_table)
___GATE2_ENTER(___ps,"c#macro-list-table",13,___LBL(13),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,8,0,___LBL(13),&___demand_attempt)){___ps->temp1=___LBL(13);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R3(___CAAR(___R2))
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_STK(1,___R3)
   ___ADJFP(1)
   ___SET_R2(___R3)
   ___SET_R3(___GLO_c_23_macro_2d_index_2d_miss)
   ___ADJFP(4)
___group_demand_commit(___ps,___LBL(13),___demand_attempt);
   ___POLL(14)
___DEF_SLBL(14,___L14_c_23_macro_2d_list_2d_table)
   ___SET_R0(___LBL(15))
   ___JUMPGLONOTSAFE(___SET_NARGS(3),105,___G_table_2d_ref)
___DEF_SLBL(15,___L15_c_23_macro_2d_list_2d_table)
   ___IF(___NOT(___EQP(___R1,___GLO_c_23_macro_2d_index_2d_miss)))
   ___GOTO(___L20_c_23_macro_2d_list_2d_table)
   ___END_IF
   ___SET_R3(___CDAR(___STK(-5)))
   ___SET_R2(___STK(-4))
   ___SET_R1(___STK(-6))
   ___SET_R0(___LBL(11))
   ___JUMPGLONOTSAFE(___SET_NARGS(3),106,___G_table_2d_set_21_)
___DEF_GLBL(___L22_c_23_macro_2d_list_2d_table)
   ___SET_R1(___VOID)
   ___JUMPRET(___R0)
___DEF_SLBL(16,___L16_c_23_macro_2d_list_2d_table)
   ___SET_R3(___STK(-5))
   ___SET_R2(___STK(-6))
   ___SET_R1(___GLO_c_23_macro_2d_list_2d_index)
   ___SET_R0(___LBL(9))
   ___JUMPGLONOTSAFE(___SET_NARGS(3),106,___G_table_2d_set_21_)
___DEF_GLBL(___L23_c_23_macro_2d_list_2d_table)
   ___ADJFP(-8)
   ___JUMPRET(___STK(1))
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_lookup
#undef ___PH_LBL0
#define ___PH_LBL0 279
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(20)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_lookup)
___DEF_P_HLBL(___L1_c_23_env_2d_lookup)
___DEF_P_HLBL(___L2_c_23_env_2d_lookup)
___DEF_P_HLBL(___L3_c_23_env_2d_lookup)
___DEF_P_HLBL(___L4_c_23_env_2d_lookup)
___DEF_P_HLBL(___L5_c_23_env_2d_lookup)
___DEF_P_HLBL(___L6_c_23_env_2d_lookup)
___DEF_P_HLBL(___L7_c_23_env_2d_lookup)
___DEF_P_HLBL(___L8_c_23_env_2d_lookup)
___DEF_P_HLBL(___L9_c_23_env_2d_lookup)
___DEF_P_HLBL(___L10_c_23_env_2d_lookup)
___DEF_P_HLBL(___L11_c_23_env_2d_lookup)
___DEF_P_HLBL(___L12_c_23_env_2d_lookup)
___DEF_P_HLBL(___L13_c_23_env_2d_lookup)
___DEF_P_HLBL(___L14_c_23_env_2d_lookup)
___DEF_P_HLBL(___L15_c_23_env_2d_lookup)
___DEF_P_HLBL(___L16_c_23_env_2d_lookup)
___DEF_P_HLBL(___L17_c_23_env_2d_lookup)
___DEF_P_HLBL(___L18_c_23_env_2d_lookup)
___DEF_P_HLBL(___L19_c_23_env_2d_lookup)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_lookup)
   ___IF_NARGS_EQ(4,___NOTHING)
   ___WRONG_NARGS(0,4,0,0)
___DEF_GLBL(___L_c_23_env_2d_lookup)
___GATE2_OPEN(___ps,"c#env-lookup",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_env_2d_lookup)
___GATE2_ENTER(___ps,"c#env-lookup",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,7,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___STK(0))
   ___ADJFP(1)
   ___SET_STK(-1,___R2)
   ___SET_STK(1,___STK(0))
   ___ADJFP(1)
   ___SET_STK(-1,___R3)
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___ADJFP(3)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___POLL(2)
___DEF_SLBL(2,___L2_c_23_env_2d_lookup)
   ___SET_R0(___LBL(3))
   ___JUMPINT(___SET_NARGS(1),___PRC(302),___L_c_23_full_2d_name_3f_)
___DEF_SLBL(3,___L3_c_23_env_2d_lookup)
   ___SET_R3(___R1)
   ___SET_R2(___STK(-3))
   ___SET_R1(___STK(-5))
   ___SET_R0(___STK(-4))
   ___ADJFP(-6)
   ___POLL(4)
___DEF_SLBL(4,___L4_c_23_env_2d_lookup)
   ___GOTO(___L20_c_23_env_2d_lookup)
___DEF_SLBL(5,___L5_c_23_env_2d_lookup)
   ___SET_R2(___VECTORREF(___STK(-8),___FIX(4L)))
   ___IF(___NOTFALSEP(___R1))
   ___GOTO(___L22_c_23_env_2d_lookup)
   ___END_IF
   ___IF(___NOTFALSEP(___STK(-11)))
   ___GOTO(___L23_c_23_env_2d_lookup)
   ___END_IF
   ___IF(___NOT(___NOTFALSEP(___R2)))
   ___GOTO(___L23_c_23_env_2d_lookup)
   ___END_IF
   ___SET_R3(___STK(-6))
   ___SET_STK(-8,___R2)
   ___SET_R2(___STK(-7))
   ___SET_R1(___STK(-8))
   ___SET_R0(___STK(-9))
   ___ADJFP(-10)
   ___POLL(6)
___DEF_SLBL(6,___L6_c_23_env_2d_lookup)
___DEF_GLBL(___L20_c_23_env_2d_lookup)
   ___IF(___NOT(___NOTFALSEP(___R3)))
   ___GOTO(___L26_c_23_env_2d_lookup)
   ___END_IF
   ___SET_R3(___TRU)
   ___POLL(7)
___DEF_SLBL(7,___L7_c_23_env_2d_lookup)
___DEF_GLBL(___L21_c_23_env_2d_lookup)
___GATE2_OPEN(___ps,"c#env-lookup",8,___LBL(8),___fp);
___DEF_SLBL(8,___L8_c_23_env_2d_lookup)
___GATE2_ENTER(___ps,"c#env-lookup",8,___LBL(8),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,10,0,___LBL(8),&___demand_attempt)){___ps->temp1=___LBL(8);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R4(___VECTORREF(___R1,___FIX(1L)))
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_STK(1,___R3)
   ___ADJFP(1)
   ___SET_R1(___R4)
   ___ADJFP(6)
___group_demand_commit(___ps,___LBL(8),___demand_attempt);
   ___POLL(9)
___DEF_SLBL(9,___L9_c_23_env_2d_lookup)
   ___SET_R0(___LBL(10))
   ___JUMPINT(___SET_NARGS(1),___PRC(261),___L_c_23_macro_2d_list_2d_table)
___DEF_SLBL(10,___L10_c_23_env_2d_lookup)
   ___SET_R2(___STK(-7))
   ___SET_R0(___LBL(11))
   ___JUMPINT(___SET_NARGS(2),___PRC(206),___L_c_23_macro_2d_list_2d_ref)
___DEF_SLBL(11,___L11_c_23_env_2d_lookup)
   ___IF(___EQP(___R1,___GLO_c_23_macro_2d_index_2d_miss))
   ___GOTO(___L25_c_23_env_2d_lookup)
   ___END_IF
___DEF_GLBL(___L22_c_23_env_2d_lookup)
   ___SET_R3(___R1)
   ___SET_R2(___STK(-7))
   ___SET_R1(___STK(-8))
   ___SET_R0(___STK(-9))
   ___POLL(12)
___DEF_SLBL(12,___L12_c_23_env_2d_lookup)
   ___GOTO(___L24_c_23_env_2d_lookup)
___DEF_GLBL(___L23_c_23_env_2d_lookup)
   ___SET_R2(___STK(-7))
   ___SET_R1(___STK(-8))
   ___SET_R3(___FAL)
   ___SET_R0(___STK(-9))
   ___POLL(13)
___DEF_SLBL(13,___L13_c_23_env_2d_lookup)
___DEF_GLBL(___L24_c_23_env_2d_lookup)
   ___ADJFP(-12)
   ___JUMPGENNOTSAFE(___SET_NARGS(3),___STK(2))
___DEF_GLBL(___L25_c_23_env_2d_lookup)
   ___SET_R2(___STK(-7))
   ___SET_R1(___STK(-8))
   ___SET_R0(___LBL(5))
   ___JUMPINT(___SET_NARGS(2),___PRC(165),___L_c_23_env_2d_frame_2d_lookup_2d_var)
___DEF_GLBL(___L26_c_23_env_2d_lookup)
___GATE2_OPEN(___ps,"c#env-lookup",14,___LBL(14),___fp);
___DEF_SLBL(14,___L14_c_23_env_2d_lookup)
___GATE2_ENTER(___ps,"c#env-lookup",14,___LBL(14),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,6,0,___LBL(14),&___demand_attempt)){___ps->temp1=___LBL(14);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___ADJFP(3)
___group_demand_commit(___ps,___LBL(14),___demand_attempt);
   ___POLL(15)
___DEF_SLBL(15,___L15_c_23_env_2d_lookup)
   ___SET_R0(___LBL(16))
   ___JUMPINT(___SET_NARGS(2),___PRC(182),___L_c_23_env_2d_namespace_2d_lookup_2d_both)
___DEF_SLBL(16,___L16_c_23_env_2d_lookup)
   ___IF(___NOTFALSEP(___R1))
   ___GOTO(___L27_c_23_env_2d_lookup)
   ___END_IF
   ___SET_R2(___STK(-3))
   ___SET_R1(___STK(-4))
   ___SET_R3(___FAL)
   ___SET_R0(___STK(-5))
   ___ADJFP(-6)
   ___POLL(17)
___DEF_SLBL(17,___L17_c_23_env_2d_lookup)
   ___GOTO(___L21_c_23_env_2d_lookup)
___DEF_GLBL(___L27_c_23_env_2d_lookup)
   ___SET_R2(___CAR(___R1))
   ___SET_R3(___CDR(___R1))
   ___SET_R4(___VECTORREF(___STK(-4),___FIX(5L)))
   ___SET_STK(-3,___R1)
   ___SET_R1(___R4)
   ___SET_R0(___LBL(18))
   ___JUMPGLONOTSAFE(___SET_NARGS(3),106,___G_table_2d_set_21_)
___DEF_SLBL(18,___L18_c_23_env_2d_lookup)
   ___SET_R2(___CAR(___STK(-3)))
   ___SET_R1(___STK(-4))
   ___SET_R3(___TRU)
   ___SET_R0(___STK(-5))
   ___ADJFP(-6)
   ___POLL(19)
___DEF_SLBL(19,___L19_c_23_env_2d_lookup)
   ___GOTO(___L21_c_23_env_2d_lookup)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_namespace_2d_valid_3f_
#undef ___PH_LBL0
#define ___PH_LBL0 300
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1 ___D_R2
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1 ___R_R2
#undef ___PW_ALL
#define ___PW_ALL ___W_R1 ___W_R2
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_namespace_2d_valid_3f_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_namespace_2d_valid_3f_)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_namespace_2d_valid_3f_)
   ___SET_R2(___STRINGLENGTH(___R1))
   ___IF(___FIXEQ(___R2,___FIX(0L)))
   ___GOTO(___L2_c_23_namespace_2d_valid_3f_)
   ___END_IF
   ___IF(___NOT(___FIXGE(___R2,___FIX(2L))))
   ___GOTO(___L1_c_23_namespace_2d_valid_3f_)
   ___END_IF
   ___SET_R2(___FIXSUB(___R2,___FIX(1L)))
   ___SET_R1(___STRINGREF(___R1,___R2))
   ___SET_R1(___BOOLEAN(___CHAREQP(___R1,___CHR(35))))
   ___JUMPRET(___R0)
___DEF_GLBL(___L1_c_23_namespace_2d_valid_3f_)
   ___SET_R1(___FAL)
   ___JUMPRET(___R0)
___DEF_GLBL(___L2_c_23_namespace_2d_valid_3f_)
   ___SET_R1(___TRU)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_full_2d_name_3f_
#undef ___PH_LBL0
#define ___PH_LBL0 302
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(6)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_full_2d_name_3f_)
___DEF_P_HLBL(___L1_c_23_full_2d_name_3f_)
___DEF_P_HLBL(___L2_c_23_full_2d_name_3f_)
___DEF_P_HLBL(___L3_c_23_full_2d_name_3f_)
___DEF_P_HLBL(___L4_c_23_full_2d_name_3f_)
___DEF_P_HLBL(___L5_c_23_full_2d_name_3f_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_full_2d_name_3f_)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_full_2d_name_3f_)
   ___IF(___SYMBOL2STRINGP_NOTFALSEP(___R2,___R1))
   ___GOTO(___L6_c_23_full_2d_name_3f_)
   ___END_IF
   ___SET_R2(___FAL)
   ___GOTO(___L10_c_23_full_2d_name_3f_)
___DEF_SLBL(1,___L1_c_23_full_2d_name_3f_)
   ___SET_R2(___R1)
   ___SET_R0(___STK(-3))
   ___ADJFP(-4)
___DEF_GLBL(___L6_c_23_full_2d_name_3f_)
___GATE2_OPEN(___ps,"c#full-name?",2,___LBL(2),___fp);
___DEF_SLBL(2,___L2_c_23_full_2d_name_3f_)
___GATE2_ENTER(___ps,"c#full-name?",2,___LBL(2),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,1,0,___LBL(2),&___demand_attempt)){___ps->temp1=___LBL(2);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R1(___STRINGLENGTH(___R2))
   ___SET_R1(___FIXSUB(___R1,___FIX(1L)))
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_R2(___R1)
   ___SET_R1(___STK(0))
   ___ADJFP(-1)
___group_demand_commit(___ps,___LBL(2),___demand_attempt);
   ___POLL(3)
___DEF_SLBL(3,___L3_c_23_full_2d_name_3f_)
___DEF_GLBL(___L7_c_23_full_2d_name_3f_)
   ___IF(___FIXLT(___R2,___FIX(0L)))
   ___GOTO(___L9_c_23_full_2d_name_3f_)
   ___END_IF
   ___SET_R3(___STRINGREF(___R1,___R2))
   ___IF(___CHAREQP(___R3,___CHR(35)))
   ___GOTO(___L8_c_23_full_2d_name_3f_)
   ___END_IF
   ___SET_R2(___FIXSUB(___R2,___FIX(1L)))
   ___POLL(4)
___DEF_SLBL(4,___L4_c_23_full_2d_name_3f_)
   ___GOTO(___L7_c_23_full_2d_name_3f_)
___DEF_GLBL(___L8_c_23_full_2d_name_3f_)
   ___SET_R1(___TRU)
   ___JUMPRET(___R0)
___DEF_GLBL(___L9_c_23_full_2d_name_3f_)
   ___SET_R1(___FAL)
   ___JUMPRET(___R0)
___DEF_GLBL(___L10_c_23_full_2d_name_3f_)
___GATE2_OPEN(___ps,"c#full-name?",5,___LBL(5),___fp);
___DEF_SLBL(5,___L5_c_23_full_2d_name_3f_)
___GATE2_ENTER(___ps,"c#full-name?",5,___LBL(5),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,4,0,___LBL(5),&___demand_attempt)){___ps->temp1=___LBL(5);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_R0(___LBL(1))
   ___ADJFP(3)
___group_demand_commit(___ps,___LBL(5),___demand_attempt);
   ___JUMPPRM(___SET_NARGS(1),___PRM__23__23_symbol_2d__3e_string)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_make_2d_full_2d_name
#undef ___PH_LBL0
#define ___PH_LBL0 309
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(7)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_make_2d_full_2d_name)
___DEF_P_HLBL(___L1_c_23_make_2d_full_2d_name)
___DEF_P_HLBL(___L2_c_23_make_2d_full_2d_name)
___DEF_P_HLBL(___L3_c_23_make_2d_full_2d_name)
___DEF_P_HLBL(___L4_c_23_make_2d_full_2d_name)
___DEF_P_HLBL(___L5_c_23_make_2d_full_2d_name)
___DEF_P_HLBL(___L6_c_23_make_2d_full_2d_name)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_make_2d_full_2d_name)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_make_2d_full_2d_name)
   ___SET_R3(___STRINGLENGTH(___R1))
   ___IF(___FIXEQ(___R3,___FIX(0L)))
   ___GOTO(___L8_c_23_make_2d_full_2d_name)
   ___END_IF
___GATE2_OPEN(___ps,"c#make-full-name",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_make_2d_full_2d_name)
___GATE2_ENTER(___ps,"c#make-full-name",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,1,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___IF(___SYMBOL2STRINGP_NOTFALSEP(___R3,___R2))
   ___GOTO(___L7_c_23_make_2d_full_2d_name)
   ___END_IF
   ___SET_R3(___FAL)
___GATE2_OPEN(___ps,"c#make-full-name",2,___LBL(2),___fp);
___DEF_SLBL(2,___L2_c_23_make_2d_full_2d_name)
___GATE2_ENTER(___ps,"c#make-full-name",2,___LBL(2),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,7,0,___LBL(2),&___demand_attempt)){___ps->temp1=___LBL(2);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_R1(___R2)
   ___SET_R0(___LBL(3))
   ___ADJFP(6)
___group_demand_commit(___ps,___LBL(2),___demand_attempt);
   ___JUMPPRM(___SET_NARGS(1),___PRM__23__23_symbol_2d__3e_string)
___DEF_SLBL(3,___L3_c_23_make_2d_full_2d_name)
   ___SET_R3(___R1)
   ___SET_R1(___STK(-6))
   ___ADJFP(-7)
___DEF_GLBL(___L7_c_23_make_2d_full_2d_name)
___GATE2_OPEN(___ps,"c#make-full-name",4,___LBL(4),___fp);
___DEF_SLBL(4,___L4_c_23_make_2d_full_2d_name)
___GATE2_ENTER(___ps,"c#make-full-name",4,___LBL(4),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,3,0,___LBL(4),&___demand_attempt)){___ps->temp1=___LBL(4);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R2(___R3)
   ___SET_R0(___LBL(5))
   ___ADJFP(3)
___group_demand_commit(___ps,___LBL(4),___demand_attempt);
   ___JUMPPRM(___SET_NARGS(2),___PRM__23__23_string_2d_append)
___DEF_SLBL(5,___L5_c_23_make_2d_full_2d_name)
   ___SET_R0(___STK(-3))
   ___POLL(6)
___DEF_SLBL(6,___L6_c_23_make_2d_full_2d_name)
   ___ADJFP(-4)
   ___JUMPPRM(___SET_NARGS(1),___PRM__23__23_string_2d__3e_symbol)
___DEF_GLBL(___L8_c_23_make_2d_full_2d_name)
   ___SET_R1(___R2)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_lookup_2d_var
#undef ___PH_LBL0
#define ___PH_LBL0 317
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(11)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_lookup_2d_var)
___DEF_P_HLBL(___L1_c_23_env_2d_lookup_2d_var)
___DEF_P_HLBL(___L2_c_23_env_2d_lookup_2d_var)
___DEF_P_HLBL(___L3_c_23_env_2d_lookup_2d_var)
___DEF_P_HLBL(___L4_c_23_env_2d_lookup_2d_var)
___DEF_P_HLBL(___L5_c_23_env_2d_lookup_2d_var)
___DEF_P_HLBL(___L6_c_23_env_2d_lookup_2d_var)
___DEF_P_HLBL(___L7_c_23_env_2d_lookup_2d_var)
___DEF_P_HLBL(___L8_c_23_env_2d_lookup_2d_var)
___DEF_P_HLBL(___L9_c_23_env_2d_lookup_2d_var)
___DEF_P_HLBL(___L10_c_23_env_2d_lookup_2d_var)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_lookup_2d_var)
   ___IF_NARGS_EQ(3,___NOTHING)
   ___WRONG_NARGS(0,3,0,0)
___DEF_GLBL(___L_c_23_env_2d_lookup_2d_var)
___GATE2_OPEN(___ps,"c#env-lookup-var",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_env_2d_lookup_2d_var)
___GATE2_ENTER(___ps,"c#env-lookup-var",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,2,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R1)
   ___ADJFP(1)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
___GATE2_OPEN(___ps,"c#env-lookup-var",2,___LBL(2),___fp);
___DEF_SLBL(2,___L2_c_23_env_2d_lookup_2d_var)
___GATE2_ENTER(___ps,"c#env-lookup-var",2,___LBL(2),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,1,4,___LBL(2),&___demand_attempt)){___ps->temp1=___LBL(2);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___ALLOC_CLO(1UL))
   ___BEGIN_SETUP_CLO(1,___STK(1),5)
   ___ADD_CLO_ELEM(0,___R3)
   ___END_SETUP_CLO(1)
   ___ADJFP(1)
   ___SET_R3(___STK(0))
   ___SET_R1(___R2)
   ___SET_R2(___FAL)
___group_demand_commit(___ps,___LBL(2),___demand_attempt);
   ___CHECK_HEAP(3,4096)
___DEF_SLBL(3,___L3_c_23_env_2d_lookup_2d_var)
   ___POLL(4)
___DEF_SLBL(4,___L4_c_23_env_2d_lookup_2d_var)
   ___ADJFP(-1)
   ___JUMPINT(___SET_NARGS(4),___PRC(279),___L_c_23_env_2d_lookup)
___DEF_SLBL(5,___L5_c_23_env_2d_lookup_2d_var)
   ___IF_NARGS_EQ(3,___NOTHING)
   ___WRONG_NARGS(5,3,0,0)
   ___IF(___NOT(___NOTFALSEP(___R3)))
   ___GOTO(___L12_c_23_env_2d_lookup_2d_var)
   ___END_IF
___GATE2_OPEN(___ps,"c#env-lookup-var",6,___LBL(6),___fp);
___DEF_SLBL(6,___L6_c_23_env_2d_lookup_2d_var)
___GATE2_ENTER(___ps,"c#env-lookup-var",6,___LBL(6),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,8,0,___LBL(6),&___demand_attempt)){___ps->temp1=___LBL(6);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_STK(1,___R3)
   ___ADJFP(1)
   ___SET_R1(___R3)
   ___ADJFP(5)
___group_demand_commit(___ps,___LBL(6),___demand_attempt);
   ___POLL(7)
___DEF_SLBL(7,___L7_c_23_env_2d_lookup_2d_var)
   ___SET_R0(___LBL(8))
   ___JUMPINT(___SET_NARGS(1),___PRC(18),___L_c_23_var_3f_)
___DEF_SLBL(8,___L8_c_23_env_2d_lookup_2d_var)
   ___IF(___NOTFALSEP(___R1))
   ___GOTO(___L11_c_23_env_2d_lookup_2d_var)
   ___END_IF
   ___SET_R2(___STK(-6))
   ___SET_R1(___SUB(0))
   ___SET_R0(___STK(-7))
   ___POLL(9)
___DEF_SLBL(9,___L9_c_23_env_2d_lookup_2d_var)
   ___ADJFP(-8)
   ___JUMPGLONOTSAFE(___SET_NARGS(2),95,___G_c_23_compiler_2d_internal_2d_error)
___DEF_GLBL(___L11_c_23_env_2d_lookup_2d_var)
   ___SET_R1(___STK(-5))
   ___ADJFP(-8)
   ___JUMPRET(___STK(1))
___DEF_GLBL(___L12_c_23_env_2d_lookup_2d_var)
   ___SET_R3(___CLO(___R4,1))
   ___POLL(10)
___DEF_SLBL(10,___L10_c_23_env_2d_lookup_2d_var)
   ___JUMPINT(___SET_NARGS(3),___PRC(107),___L_c_23_env_2d_new_2d_var_21_)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_define_2d_var
#undef ___PH_LBL0
#define ___PH_LBL0 329
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(12)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_define_2d_var)
___DEF_P_HLBL(___L1_c_23_env_2d_define_2d_var)
___DEF_P_HLBL(___L2_c_23_env_2d_define_2d_var)
___DEF_P_HLBL(___L3_c_23_env_2d_define_2d_var)
___DEF_P_HLBL(___L4_c_23_env_2d_define_2d_var)
___DEF_P_HLBL(___L5_c_23_env_2d_define_2d_var)
___DEF_P_HLBL(___L6_c_23_env_2d_define_2d_var)
___DEF_P_HLBL(___L7_c_23_env_2d_define_2d_var)
___DEF_P_HLBL(___L8_c_23_env_2d_define_2d_var)
___DEF_P_HLBL(___L9_c_23_env_2d_define_2d_var)
___DEF_P_HLBL(___L10_c_23_env_2d_define_2d_var)
___DEF_P_HLBL(___L11_c_23_env_2d_define_2d_var)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_define_2d_var)
   ___IF_NARGS_EQ(3,___NOTHING)
   ___WRONG_NARGS(0,3,0,0)
___DEF_GLBL(___L_c_23_env_2d_define_2d_var)
___GATE2_OPEN(___ps,"c#env-define-var",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_env_2d_define_2d_var)
___GATE2_ENTER(___ps,"c#env-define-var",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,2,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R1)
   ___ADJFP(1)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
___GATE2_OPEN(___ps,"c#env-define-var",2,___LBL(2),___fp);
___DEF_SLBL(2,___L2_c_23_env_2d_define_2d_var)
___GATE2_ENTER(___ps,"c#env-define-var",2,___LBL(2),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,1,4,___LBL(2),&___demand_attempt)){___ps->temp1=___LBL(2);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___ALLOC_CLO(1UL))
   ___BEGIN_SETUP_CLO(1,___STK(1),5)
   ___ADD_CLO_ELEM(0,___R3)
   ___END_SETUP_CLO(1)
   ___ADJFP(1)
   ___SET_R3(___STK(0))
   ___SET_R1(___R2)
   ___SET_R2(___TRU)
___group_demand_commit(___ps,___LBL(2),___demand_attempt);
   ___CHECK_HEAP(3,4096)
___DEF_SLBL(3,___L3_c_23_env_2d_define_2d_var)
   ___POLL(4)
___DEF_SLBL(4,___L4_c_23_env_2d_define_2d_var)
   ___ADJFP(-1)
   ___JUMPINT(___SET_NARGS(4),___PRC(279),___L_c_23_env_2d_lookup)
___DEF_SLBL(5,___L5_c_23_env_2d_define_2d_var)
   ___IF_NARGS_EQ(3,___NOTHING)
   ___WRONG_NARGS(5,3,0,0)
   ___IF(___NOT(___NOTFALSEP(___R3)))
   ___GOTO(___L13_c_23_env_2d_define_2d_var)
   ___END_IF
___GATE2_OPEN(___ps,"c#env-define-var",6,___LBL(6),___fp);
___DEF_SLBL(6,___L6_c_23_env_2d_define_2d_var)
___GATE2_ENTER(___ps,"c#env-define-var",6,___LBL(6),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,8,0,___LBL(6),&___demand_attempt)){___ps->temp1=___LBL(6);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_STK(1,___R4)
   ___ADJFP(1)
   ___SET_R1(___R3)
   ___ADJFP(5)
___group_demand_commit(___ps,___LBL(6),___demand_attempt);
   ___POLL(7)
___DEF_SLBL(7,___L7_c_23_env_2d_define_2d_var)
   ___SET_R0(___LBL(8))
   ___JUMPINT(___SET_NARGS(1),___PRC(18),___L_c_23_var_3f_)
___DEF_SLBL(8,___L8_c_23_env_2d_define_2d_var)
   ___IF(___NOT(___NOTFALSEP(___R1)))
   ___GOTO(___L12_c_23_env_2d_define_2d_var)
   ___END_IF
   ___SET_R1(___CLO(___STK(-5),1))
   ___SET_R2(___SUB(1))
   ___SET_R0(___STK(-7))
   ___POLL(9)
___DEF_SLBL(9,___L9_c_23_env_2d_define_2d_var)
   ___ADJFP(-8)
   ___JUMPGLONOTSAFE(___SET_NARGS(2),99,___G_c_23_pt_2d_syntax_2d_error)
___DEF_GLBL(___L12_c_23_env_2d_define_2d_var)
   ___SET_R2(___STK(-6))
   ___SET_R1(___SUB(2))
   ___SET_R0(___STK(-7))
   ___POLL(10)
___DEF_SLBL(10,___L10_c_23_env_2d_define_2d_var)
   ___ADJFP(-8)
   ___JUMPGLONOTSAFE(___SET_NARGS(2),95,___G_c_23_compiler_2d_internal_2d_error)
___DEF_GLBL(___L13_c_23_env_2d_define_2d_var)
   ___SET_R3(___CLO(___R4,1))
   ___POLL(11)
___DEF_SLBL(11,___L11_c_23_env_2d_define_2d_var)
   ___JUMPINT(___SET_NARGS(3),___PRC(107),___L_c_23_env_2d_new_2d_var_21_)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_lookup_2d_global_2d_var
#undef ___PH_LBL0
#define ___PH_LBL0 342
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(6)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_lookup_2d_global_2d_var)
___DEF_P_HLBL(___L1_c_23_env_2d_lookup_2d_global_2d_var)
___DEF_P_HLBL(___L2_c_23_env_2d_lookup_2d_global_2d_var)
___DEF_P_HLBL(___L3_c_23_env_2d_lookup_2d_global_2d_var)
___DEF_P_HLBL(___L4_c_23_env_2d_lookup_2d_global_2d_var)
___DEF_P_HLBL(___L5_c_23_env_2d_lookup_2d_global_2d_var)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_lookup_2d_global_2d_var)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_env_2d_lookup_2d_global_2d_var)
___GATE2_OPEN(___ps,"c#env-lookup-global-var",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_env_2d_lookup_2d_global_2d_var)
___GATE2_ENTER(___ps,"c#env-lookup-global-var",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,8,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___ADJFP(6)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___POLL(2)
___DEF_SLBL(2,___L2_c_23_env_2d_lookup_2d_global_2d_var)
   ___SET_R0(___LBL(3))
   ___JUMPINT(___SET_NARGS(1),___PRC(354),___L_c_23_env_2d_global_2d_env)
___DEF_SLBL(3,___L3_c_23_env_2d_lookup_2d_global_2d_var)
   ___SET_STK(-5,___R1)
   ___SET_R2(___STK(-6))
   ___SET_R0(___LBL(4))
   ___JUMPINT(___SET_NARGS(2),___PRC(165),___L_c_23_env_2d_frame_2d_lookup_2d_var)
___DEF_SLBL(4,___L4_c_23_env_2d_lookup_2d_global_2d_var)
   ___IF(___NOTFALSEP(___R1))
   ___GOTO(___L6_c_23_env_2d_lookup_2d_global_2d_var)
   ___END_IF
   ___SET_R2(___STK(-6))
   ___SET_R1(___STK(-5))
   ___SET_R3(___FAL)
   ___SET_R0(___STK(-7))
   ___POLL(5)
___DEF_SLBL(5,___L5_c_23_env_2d_lookup_2d_global_2d_var)
   ___ADJFP(-8)
   ___JUMPINT(___SET_NARGS(3),___PRC(107),___L_c_23_env_2d_new_2d_var_21_)
___DEF_GLBL(___L6_c_23_env_2d_lookup_2d_global_2d_var)
   ___ADJFP(-8)
   ___JUMPRET(___STK(1))
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_global_2d_variables
#undef ___PH_LBL0
#define ___PH_LBL0 349
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(4)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_global_2d_variables)
___DEF_P_HLBL(___L1_c_23_env_2d_global_2d_variables)
___DEF_P_HLBL(___L2_c_23_env_2d_global_2d_variables)
___DEF_P_HLBL(___L3_c_23_env_2d_global_2d_variables)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_global_2d_variables)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_env_2d_global_2d_variables)
___GATE2_OPEN(___ps,"c#env-global-variables",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_env_2d_global_2d_variables)
___GATE2_ENTER(___ps,"c#env-global-variables",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,4,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___ADJFP(3)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___POLL(2)
___DEF_SLBL(2,___L2_c_23_env_2d_global_2d_variables)
   ___SET_R0(___LBL(3))
   ___JUMPINT(___SET_NARGS(1),___PRC(354),___L_c_23_env_2d_global_2d_env)
___DEF_SLBL(3,___L3_c_23_env_2d_global_2d_variables)
   ___SET_R1(___VECTORREF(___R1,___FIX(0L)))
   ___SET_R1(___CAR(___R1))
   ___ADJFP(-4)
   ___JUMPRET(___STK(1))
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_global_2d_env
#undef ___PH_LBL0
#define ___PH_LBL0 354
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_FP ___D_R0 ___D_R1 ___D_R2
#undef ___PR_ALL
#define ___PR_ALL ___R_FP ___R_R0 ___R_R1 ___R_R2
#undef ___PW_ALL
#define ___PW_ALL ___W_R1 ___W_R2
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(3)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_global_2d_env)
___DEF_P_HLBL(___L1_c_23_env_2d_global_2d_env)
___DEF_P_HLBL(___L2_c_23_env_2d_global_2d_env)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_global_2d_env)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_env_2d_global_2d_env)
   ___POLL(1)
___DEF_SLBL(1,___L1_c_23_env_2d_global_2d_env)
   ___GOTO(___L4_c_23_env_2d_global_2d_env)
___DEF_GLBL(___L3_c_23_env_2d_global_2d_env)
   ___SET_R1(___R2)
   ___POLL(2)
___DEF_SLBL(2,___L2_c_23_env_2d_global_2d_env)
___DEF_GLBL(___L4_c_23_env_2d_global_2d_env)
   ___SET_R2(___VECTORREF(___R1,___FIX(4L)))
   ___IF(___NOTFALSEP(___R2))
   ___GOTO(___L3_c_23_env_2d_global_2d_env)
   ___END_IF
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2d_lookup_2d_macro
#undef ___PH_LBL0
#define ___PH_LBL0 358
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(7)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2d_lookup_2d_macro)
___DEF_P_HLBL(___L1_c_23_env_2d_lookup_2d_macro)
___DEF_P_HLBL(___L2_c_23_env_2d_lookup_2d_macro)
___DEF_P_HLBL(___L3_c_23_env_2d_lookup_2d_macro)
___DEF_P_HLBL(___L4_c_23_env_2d_lookup_2d_macro)
___DEF_P_HLBL(___L5_c_23_env_2d_lookup_2d_macro)
___DEF_P_HLBL(___L6_c_23_env_2d_lookup_2d_macro)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2d_lookup_2d_macro)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_env_2d_lookup_2d_macro)
___GATE2_OPEN(___ps,"c#env-lookup-macro",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_env_2d_lookup_2d_macro)
___GATE2_ENTER(___ps,"c#env-lookup-macro",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,1,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_R3(___LBL(3))
   ___SET_R1(___R2)
   ___SET_R2(___FAL)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___POLL(2)
___DEF_SLBL(2,___L2_c_23_env_2d_lookup_2d_macro)
   ___JUMPINT(___SET_NARGS(4),___PRC(279),___L_c_23_env_2d_lookup)
___DEF_SLBL(3,___L3_c_23_env_2d_lookup_2d_macro)
   ___IF_NARGS_EQ(3,___NOTHING)
   ___WRONG_NARGS(3,3,0,0)
   ___IF(___NOT(___NOTFALSEP(___R3)))
   ___GOTO(___L7_c_23_env_2d_lookup_2d_macro)
   ___END_IF
___GATE2_OPEN(___ps,"c#env-lookup-macro",4,___LBL(4),___fp);
___DEF_SLBL(4,___L4_c_23_env_2d_lookup_2d_macro)
___GATE2_ENTER(___ps,"c#env-lookup-macro",4,___LBL(4),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,8,0,___LBL(4),&___demand_attempt)){___ps->temp1=___LBL(4);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R3)
   ___ADJFP(1)
   ___SET_R1(___R3)
   ___ADJFP(6)
___group_demand_commit(___ps,___LBL(4),___demand_attempt);
   ___POLL(5)
___DEF_SLBL(5,___L5_c_23_env_2d_lookup_2d_macro)
   ___SET_R0(___LBL(6))
   ___JUMPINT(___SET_NARGS(1),___PRC(18),___L_c_23_var_3f_)
___DEF_SLBL(6,___L6_c_23_env_2d_lookup_2d_macro)
   ___IF(___NOT(___NOTFALSEP(___R1)))
   ___GOTO(___L8_c_23_env_2d_lookup_2d_macro)
   ___END_IF
   ___SET_R0(___STK(-7))
   ___ADJFP(-8)
___DEF_GLBL(___L7_c_23_env_2d_lookup_2d_macro)
   ___SET_R1(___FAL)
   ___JUMPRET(___R0)
___DEF_GLBL(___L8_c_23_env_2d_lookup_2d_macro)
   ___SET_R1(___STK(-6))
   ___ADJFP(-8)
   ___JUMPRET(___STK(1))
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_define_2d_flag_2d_decl
#undef ___PH_LBL0
#define ___PH_LBL0 366
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(3)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_define_2d_flag_2d_decl)
___DEF_P_HLBL(___L1_c_23_define_2d_flag_2d_decl)
___DEF_P_HLBL(___L2_c_23_define_2d_flag_2d_decl)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_define_2d_flag_2d_decl)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_define_2d_flag_2d_decl)
___GATE2_OPEN(___ps,"c#define-flag-decl",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_define_2d_flag_2d_decl)
___GATE2_ENTER(___ps,"c#define-flag-decl",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,8,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R1(___CONS(___R1,___R2))
   ___SET_R1(___CONS(___R1,___GLO_c_23_flag_2d_declarations))
   ___SET_GLO(38,___G_c_23_flag_2d_declarations,___R1)
   ___SET_R1(___NUL)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___CHECK_HEAP(2,4096)
___DEF_SLBL(2,___L2_c_23_define_2d_flag_2d_decl)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_define_2d_parameterized_2d_decl
#undef ___PH_LBL0
#define ___PH_LBL0 370
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(3)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_define_2d_parameterized_2d_decl)
___DEF_P_HLBL(___L1_c_23_define_2d_parameterized_2d_decl)
___DEF_P_HLBL(___L2_c_23_define_2d_parameterized_2d_decl)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_define_2d_parameterized_2d_decl)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_define_2d_parameterized_2d_decl)
___GATE2_OPEN(___ps,"c#define-parameterized-decl",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_define_2d_parameterized_2d_decl)
___GATE2_ENTER(___ps,"c#define-parameterized-decl",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,8,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R1(___CONS(___R1,___R2))
   ___SET_R1(___CONS(___R1,___GLO_c_23_parameterized_2d_declarations))
   ___SET_GLO(63,___G_c_23_parameterized_2d_declarations,___R1)
   ___SET_R1(___NUL)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___CHECK_HEAP(2,4096)
___DEF_SLBL(2,___L2_c_23_define_2d_parameterized_2d_decl)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_define_2d_boolean_2d_decl
#undef ___PH_LBL0
#define ___PH_LBL0 374
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(3)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_define_2d_boolean_2d_decl)
___DEF_P_HLBL(___L1_c_23_define_2d_boolean_2d_decl)
___DEF_P_HLBL(___L2_c_23_define_2d_boolean_2d_decl)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_define_2d_boolean_2d_decl)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_define_2d_boolean_2d_decl)
___GATE2_OPEN(___ps,"c#define-boolean-decl",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_define_2d_boolean_2d_decl)
___GATE2_ENTER(___ps,"c#define-boolean-decl",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,4,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R1(___CONS(___R1,___GLO_c_23_boolean_2d_declarations))
   ___SET_GLO(2,___G_c_23_boolean_2d_declarations,___R1)
   ___SET_R1(___NUL)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___CHECK_HEAP(2,4096)
___DEF_SLBL(2,___L2_c_23_define_2d_boolean_2d_decl)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_define_2d_namable_2d_decl
#undef ___PH_LBL0
#define ___PH_LBL0 378
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(3)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_define_2d_namable_2d_decl)
___DEF_P_HLBL(___L1_c_23_define_2d_namable_2d_decl)
___DEF_P_HLBL(___L2_c_23_define_2d_namable_2d_decl)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_define_2d_namable_2d_decl)
   ___IF_NARGS_EQ(2,___NOTHING)
   ___WRONG_NARGS(0,2,0,0)
___DEF_GLBL(___L_c_23_define_2d_namable_2d_decl)
___GATE2_OPEN(___ps,"c#define-namable-decl",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_define_2d_namable_2d_decl)
___GATE2_ENTER(___ps,"c#define-namable-decl",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,8,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R1(___CONS(___R1,___R2))
   ___SET_R1(___CONS(___R1,___GLO_c_23_namable_2d_declarations))
   ___SET_GLO(59,___G_c_23_namable_2d_declarations,___R1)
   ___SET_R1(___NUL)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___CHECK_HEAP(2,4096)
___DEF_SLBL(2,___L2_c_23_define_2d_namable_2d_decl)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_define_2d_namable_2d_boolean_2d_decl
#undef ___PH_LBL0
#define ___PH_LBL0 382
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(3)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_define_2d_namable_2d_boolean_2d_decl)
___DEF_P_HLBL(___L1_c_23_define_2d_namable_2d_boolean_2d_decl)
___DEF_P_HLBL(___L2_c_23_define_2d_namable_2d_boolean_2d_decl)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_define_2d_namable_2d_boolean_2d_decl)
   ___IF_NARGS_EQ(1,___NOTHING)
   ___WRONG_NARGS(0,1,0,0)
___DEF_GLBL(___L_c_23_define_2d_namable_2d_boolean_2d_decl)
___GATE2_OPEN(___ps,"c#define-namable-boolean-decl",1,___LBL(1)
,___fp);
___DEF_SLBL(1,___L1_c_23_define_2d_namable_2d_boolean_2d_decl)
___GATE2_ENTER(___ps,"c#define-namable-boolean-decl",1,___LBL(1)
,___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,4,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R1(___CONS(___R1,___GLO_c_23_namable_2d_boolean_2d_declarations))
   ___SET_GLO(57,___G_c_23_namable_2d_boolean_2d_declarations,___R1)
   ___SET_R1(___NUL)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___CHECK_HEAP(2,4096)
___DEF_SLBL(2,___L2_c_23_define_2d_namable_2d_boolean_2d_decl)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_flag_2d_decl
#undef ___PH_LBL0
#define ___PH_LBL0 386
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(3)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_flag_2d_decl)
___DEF_P_HLBL(___L1_c_23_flag_2d_decl)
___DEF_P_HLBL(___L2_c_23_flag_2d_decl)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_flag_2d_decl)
   ___IF_NARGS_EQ(3,___NOTHING)
   ___WRONG_NARGS(0,3,0,0)
___DEF_GLBL(___L_c_23_flag_2d_decl)
___GATE2_OPEN(___ps,"c#flag-decl",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_flag_2d_decl)
___GATE2_ENTER(___ps,"c#flag-decl",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,8,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___BEGIN_ALLOC_LIST(2UL,___R3)
   ___ADD_LIST_ELEM(1,___R2)
   ___END_ALLOC_LIST(2)
   ___SET_R1(___GET_LIST(2))
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___CHECK_HEAP(2,4096)
___DEF_SLBL(2,___L2_c_23_flag_2d_decl)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_parameterized_2d_decl
#undef ___PH_LBL0
#define ___PH_LBL0 390
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(3)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_parameterized_2d_decl)
___DEF_P_HLBL(___L1_c_23_parameterized_2d_decl)
___DEF_P_HLBL(___L2_c_23_parameterized_2d_decl)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_parameterized_2d_decl)
   ___IF_NARGS_EQ(3,___NOTHING)
   ___WRONG_NARGS(0,3,0,0)
___DEF_GLBL(___L_c_23_parameterized_2d_decl)
___GATE2_OPEN(___ps,"c#parameterized-decl",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_parameterized_2d_decl)
___GATE2_ENTER(___ps,"c#parameterized-decl",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,8,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___BEGIN_ALLOC_LIST(2UL,___R3)
   ___ADD_LIST_ELEM(1,___R2)
   ___END_ALLOC_LIST(2)
   ___SET_R1(___GET_LIST(2))
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___CHECK_HEAP(2,4096)
___DEF_SLBL(2,___L2_c_23_parameterized_2d_decl)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_boolean_2d_decl
#undef ___PH_LBL0
#define ___PH_LBL0 394
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(3)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_boolean_2d_decl)
___DEF_P_HLBL(___L1_c_23_boolean_2d_decl)
___DEF_P_HLBL(___L2_c_23_boolean_2d_decl)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_boolean_2d_decl)
   ___IF_NARGS_EQ(3,___NOTHING)
   ___WRONG_NARGS(0,3,0,0)
___DEF_GLBL(___L_c_23_boolean_2d_decl)
___GATE2_OPEN(___ps,"c#boolean-decl",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_boolean_2d_decl)
___GATE2_ENTER(___ps,"c#boolean-decl",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,8,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___BEGIN_ALLOC_LIST(2UL,___R3)
   ___ADD_LIST_ELEM(1,___R2)
   ___END_ALLOC_LIST(2)
   ___SET_R1(___GET_LIST(2))
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___CHECK_HEAP(2,4096)
___DEF_SLBL(2,___L2_c_23_boolean_2d_decl)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_namable_2d_decl
#undef ___PH_LBL0
#define ___PH_LBL0 398
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R1 ___W_R2
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(3)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_namable_2d_decl)
___DEF_P_HLBL(___L1_c_23_namable_2d_decl)
___DEF_P_HLBL(___L2_c_23_namable_2d_decl)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_namable_2d_decl)
   ___IF_NARGS_EQ(4,___NOTHING)
   ___WRONG_NARGS(0,4,0,0)
___DEF_GLBL(___L_c_23_namable_2d_decl)
___GATE2_OPEN(___ps,"c#namable-decl",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_namable_2d_decl)
___GATE2_ENTER(___ps,"c#namable-decl",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,8,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R2(___CONS(___R2,___R3))
   ___SET_R1(___CONS(___R1,___R2))
   ___ADJFP(-1)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___CHECK_HEAP(2,4096)
___DEF_SLBL(2,___L2_c_23_namable_2d_decl)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_namable_2d_boolean_2d_decl
#undef ___PH_LBL0
#define ___PH_LBL0 402
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R1 ___W_R2
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(3)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_namable_2d_boolean_2d_decl)
___DEF_P_HLBL(___L1_c_23_namable_2d_boolean_2d_decl)
___DEF_P_HLBL(___L2_c_23_namable_2d_boolean_2d_decl)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_namable_2d_boolean_2d_decl)
   ___IF_NARGS_EQ(4,___NOTHING)
   ___WRONG_NARGS(0,4,0,0)
___DEF_GLBL(___L_c_23_namable_2d_boolean_2d_decl)
___GATE2_OPEN(___ps,"c#namable-boolean-decl",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_namable_2d_boolean_2d_decl)
___GATE2_ENTER(___ps,"c#namable-boolean-decl",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,0,8,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R2(___CONS(___R2,___R3))
   ___SET_R1(___CONS(___R1,___R2))
   ___ADJFP(-1)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___CHECK_HEAP(2,4096)
___DEF_SLBL(2,___L2_c_23_namable_2d_boolean_2d_decl)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_declaration_2d_value
#undef ___PH_LBL0
#define ___PH_LBL0 406
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R2 ___D_R3 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R2 ___R_R3 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R2 ___W_R3 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(8)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_declaration_2d_value)
___DEF_P_HLBL(___L1_c_23_declaration_2d_value)
___DEF_P_HLBL(___L2_c_23_declaration_2d_value)
___DEF_P_HLBL(___L3_c_23_declaration_2d_value)
___DEF_P_HLBL(___L4_c_23_declaration_2d_value)
___DEF_P_HLBL(___L5_c_23_declaration_2d_value)
___DEF_P_HLBL(___L6_c_23_declaration_2d_value)
___DEF_P_HLBL(___L7_c_23_declaration_2d_value)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_declaration_2d_value)
   ___IF_NARGS_EQ(4,___NOTHING)
   ___WRONG_NARGS(0,4,0,0)
___DEF_GLBL(___L_c_23_declaration_2d_value)
   ___SET_R3(___VECTORREF(___R3,___FIX(2L)))
   ___POLL(1)
___DEF_SLBL(1,___L1_c_23_declaration_2d_value)
   ___GOTO(___L9_c_23_declaration_2d_value)
___DEF_SLBL(2,___L2_c_23_declaration_2d_value)
   ___IF(___NOTFALSEP(___R1))
   ___GOTO(___L13_c_23_declaration_2d_value)
   ___END_IF
   ___SET_R3(___STK(-6))
   ___SET_R2(___STK(-7))
   ___SET_R1(___STK(-8))
   ___SET_R0(___STK(-9))
   ___ADJFP(-10)
___DEF_GLBL(___L8_c_23_declaration_2d_value)
   ___SET_R3(___CDR(___R3))
   ___ADJFP(-1)
   ___POLL(3)
___DEF_SLBL(3,___L3_c_23_declaration_2d_value)
___DEF_GLBL(___L9_c_23_declaration_2d_value)
   ___IF(___NOT(___PAIRP(___R3)))
   ___GOTO(___L15_c_23_declaration_2d_value)
   ___END_IF
___GATE2_OPEN(___ps,"c#declaration-value",4,___LBL(4),___fp);
___DEF_SLBL(4,___L4_c_23_declaration_2d_value)
___GATE2_ENTER(___ps,"c#declaration-value",4,___LBL(4),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,1,0,___LBL(4),&___demand_attempt)){___ps->temp1=___LBL(4);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_R4(___CAR(___R3))
   ___SET_STK(1,___CAR(___R4))
   ___ADJFP(1)
___group_demand_commit(___ps,___LBL(4),___demand_attempt);
   ___IF(___NOT(___EQP(___STK(0),___STK(-1))))
   ___GOTO(___L8_c_23_declaration_2d_value)
   ___END_IF
   ___SET_STK(0,___CDDR(___R4))
   ___IF(___NULLP(___STK(0)))
   ___GOTO(___L14_c_23_declaration_2d_value)
   ___END_IF
___GATE2_OPEN(___ps,"c#declaration-value",5,___LBL(5),___fp);
___DEF_SLBL(5,___L5_c_23_declaration_2d_value)
___GATE2_ENTER(___ps,"c#declaration-value",5,___LBL(5),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,10,0,___LBL(5),&___demand_attempt)){___ps->temp1=___LBL(5);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(0,___CDDR(___R4))
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_STK(1,___R1)
   ___ADJFP(1)
   ___SET_STK(1,___R2)
   ___ADJFP(1)
   ___SET_STK(1,___R3)
   ___ADJFP(1)
   ___SET_STK(1,___R4)
   ___ADJFP(1)
   ___SET_R2(___STK(-5))
   ___SET_R0(___LBL(2))
   ___ADJFP(5)
___group_demand_commit(___ps,___LBL(5),___demand_attempt);
   ___POLL(6)
___DEF_SLBL(6,___L6_c_23_declaration_2d_value)
___DEF_GLBL(___L10_c_23_declaration_2d_value)
   ___IF(___NOT(___PAIRP(___R2)))
   ___GOTO(___L12_c_23_declaration_2d_value)
   ___END_IF
   ___SET_R3(___CAR(___R2))
   ___IF(___EQP(___R1,___R3))
   ___GOTO(___L11_c_23_declaration_2d_value)
   ___END_IF
   ___SET_R2(___CDR(___R2))
   ___POLL(7)
___DEF_SLBL(7,___L7_c_23_declaration_2d_value)
   ___GOTO(___L10_c_23_declaration_2d_value)
___DEF_GLBL(___L11_c_23_declaration_2d_value)
   ___SET_R1(___R2)
   ___JUMPRET(___R0)
___DEF_GLBL(___L12_c_23_declaration_2d_value)
   ___SET_R1(___FAL)
   ___JUMPRET(___R0)
___DEF_GLBL(___L13_c_23_declaration_2d_value)
   ___SET_R4(___STK(-5))
   ___SET_R0(___STK(-9))
   ___ADJFP(-10)
___DEF_GLBL(___L14_c_23_declaration_2d_value)
   ___SET_R1(___CADR(___R4))
   ___ADJFP(-2)
   ___JUMPRET(___R0)
___DEF_GLBL(___L15_c_23_declaration_2d_value)
   ___SET_R1(___R2)
   ___ADJFP(-1)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2e_begin_21_
#undef ___PH_LBL0
#define ___PH_LBL0 415
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_HEAP ___D_FP ___D_R0 ___D_R1 ___D_R4
#undef ___PR_ALL
#define ___PR_ALL ___R_HEAP ___R_FP ___R_R0 ___R_R1 ___R_R4
#undef ___PW_ALL
#define ___PW_ALL ___W_HEAP ___W_FP ___W_R0 ___W_R1 ___W_R4
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(8)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2e_begin_21_)
___DEF_P_HLBL(___L1_c_23_env_2e_begin_21_)
___DEF_P_HLBL(___L2_c_23_env_2e_begin_21_)
___DEF_P_HLBL(___L3_c_23_env_2e_begin_21_)
___DEF_P_HLBL(___L4_c_23_env_2e_begin_21_)
___DEF_P_HLBL(___L5_c_23_env_2e_begin_21_)
___DEF_P_HLBL(___L6_c_23_env_2e_begin_21_)
___DEF_P_HLBL(___L7_c_23_env_2e_begin_21_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2e_begin_21_)
   ___IF_NARGS_EQ(0,___NOTHING)
   ___WRONG_NARGS(0,0,0,0)
___DEF_GLBL(___L_c_23_env_2e_begin_21_)
___GATE2_OPEN(___ps,"c#env.begin!",1,___LBL(1),___fp);
___DEF_SLBL(1,___L1_c_23_env_2e_begin_21_)
___GATE2_ENTER(___ps,"c#env.begin!",1,___LBL(1),___fp);
if(!___group_demand_enter(___ps,&___hp,&___fp,4,0,___LBL(1),&___demand_attempt)){___ps->temp1=___LBL(1);___JUMPEXTPRM(___NOTHING,___ps->handler_stack_limit);}
   ___SET_STK(1,___R0)
   ___ADJFP(1)
   ___SET_R1(___FIX(0L))
   ___ADJFP(3)
___group_demand_commit(___ps,___LBL(1),___demand_attempt);
   ___POLL(2)
___DEF_SLBL(2,___L2_c_23_env_2e_begin_21_)
   ___SET_R0(___LBL(3))
   ___JUMPGLONOTSAFE(___SET_NARGS(1),96,___G_c_23_make_2d_counter)
___DEF_SLBL(3,___L3_c_23_env_2e_begin_21_)
   ___SET_GLO(61,___G_c_23_next_2d_var_2d_stamp,___R1)
   ___SET_R1(___SYM_ret)
   ___SET_R0(___LBL(4))
   ___JUMPINT(___SET_NARGS(1),___PRC(74),___L_c_23_make_2d_temp_2d_var)
___DEF_SLBL(4,___L4_c_23_env_2e_begin_21_)
   ___SET_GLO(65,___G_c_23_ret_2d_var,___R1)
   ___SET_R1(___GLO_c_23_ret_2d_var)
   ___SET_R0(___LBL(5))
   ___JUMPGLONOTSAFE(___SET_NARGS(1),101,___G_c_23_varset_2d_singleton)
___DEF_SLBL(5,___L5_c_23_env_2e_begin_21_)
   ___SET_GLO(66,___G_c_23_ret_2d_var_2d_set,___R1)
   ___SET_R1(___SYM_closure_2d_env)
   ___SET_R0(___LBL(6))
   ___JUMPINT(___SET_NARGS(1),___PRC(74),___L_c_23_make_2d_temp_2d_var)
___DEF_SLBL(6,___L6_c_23_env_2e_begin_21_)
   ___SET_GLO(3,___G_c_23_closure_2d_env_2d_var,___R1)
   ___SET_R1(___FAL)
   ___SET_R0(___LBL(7))
   ___JUMPINT(___SET_NARGS(1),___PRC(74),___L_c_23_make_2d_temp_2d_var)
___DEF_SLBL(7,___L7_c_23_env_2e_begin_21_)
   ___SET_GLO(10,___G_c_23_empty_2d_var,___R1)
   ___SET_R1(___NUL)
   ___ADJFP(-4)
   ___JUMPRET(___STK(1))
___END_P_SW
___END_P_COD

#undef ___PH_PROC
#define ___PH_PROC ___H_c_23_env_2e_end_21_
#undef ___PH_LBL0
#define ___PH_LBL0 424
#undef ___PD_ALL
#define ___PD_ALL ___WORD ___demand_attempt=0; ___D_R0 ___D_R1
#undef ___PR_ALL
#define ___PR_ALL ___R_R0 ___R_R1
#undef ___PW_ALL
#define ___PW_ALL ___W_R1
___BEGIN_P_COD
___BEGIN_P_HLBL_AT(1)
___DEF_P_HLBL_INTRO_AT
___DEF_P_HLBL(___L0_c_23_env_2e_end_21_)
___END_P_HLBL
___BEGIN_P_SW
___DEF_SLBL(0,___L0_c_23_env_2e_end_21_)
   ___IF_NARGS_EQ(0,___NOTHING)
   ___WRONG_NARGS(0,0,0,0)
___DEF_GLBL(___L_c_23_env_2e_end_21_)
   ___SET_GLO(61,___G_c_23_next_2d_var_2d_stamp,___NUL)
   ___SET_GLO(65,___G_c_23_ret_2d_var,___NUL)
   ___SET_GLO(66,___G_c_23_ret_2d_var_2d_set,___NUL)
   ___SET_GLO(3,___G_c_23_closure_2d_env_2d_var,___NUL)
   ___SET_GLO(10,___G_c_23_empty_2d_var,___NUL)
   ___SET_R1(___NUL)
   ___JUMPRET(___R0)
___END_P_SW
___END_P_COD

___END_M_SW
___END_M_COD

___BEGIN_LBL
 ___DEF_LBL_INTRO(___H___env_23_,___REF_SYM(1,___S___env_23_),___REF_FAL,9,0)
,___DEF_LBL_PROC_AT(___H___env_23_,0,-1,1)
,___DEF_LBL_RET_AT(___H___env_23_,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H___env_23_,___IFD(___RETI,5,0,0x3f11L),3)
,___DEF_LBL_RET_AT(___H___env_23_,___IFD(___RETI,5,0,0x3f11L),4)
,___DEF_LBL_RET_AT(___H___env_23_,___IFD(___RETN,1,0,0x1L),5)
,___DEF_LBL_RET_AT(___H___env_23_,___IFD(___RETI,4,0,0x3f1L),6)
,___DEF_LBL_RET_AT(___H___env_23_,___IFD(___RETI,1,0,0x3f1L),7)
,___DEF_LBL_PROC_AT(___H___env_23_,0,-1,8)
,___DEF_LBL_RET_AT(___H___env_23_,___IFD(___RETI,0,0,0x3fL),9)
,___DEF_LBL_INTRO(___H_c_23_make_2d_var,___REF_SYM(48,___S_c_23_make_2d_var),___REF_FAL,6,0)
,___DEF_LBL_PROC_AT(___H_c_23_make_2d_var,6,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_make_2d_var,___IFD(___RETI,3,4,0x3f7L),2)
,___DEF_LBL_RET_AT(___H_c_23_make_2d_var,___OFD(___RETI,12,3,0x3f07fL),3)
,___DEF_LBL_RET_AT(___H_c_23_make_2d_var,___IFD(___RETN,9,3,0x7fL),4)
,___DEF_LBL_RET_AT(___H_c_23_make_2d_var,___OFD(___RETI,12,3,0x3f07fL),5)
,___DEF_LBL_RET_AT(___H_c_23_make_2d_var,___IFD(___RETI,4,3,0x3f8L),6)
,___DEF_LBL_INTRO(___H_c_23_var_3f_,___REF_SYM(77,___S_c_23_var_3f_),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_3f_,1,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_name,___REF_SYM(65,___S_c_23_var_2d_name),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_name,1,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_bound,___REF_SYM(54,___S_c_23_var_2d_bound),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_bound,1,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_refs,___REF_SYM(67,___S_c_23_var_2d_refs),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_refs,1,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_sets,___REF_SYM(69,___S_c_23_var_2d_sets),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_sets,1,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_source,___REF_SYM(71,___S_c_23_var_2d_source),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_source,1,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_boxed_3f_,___REF_SYM(56,___S_c_23_var_2d_boxed_3f_),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_boxed_3f_,1,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_info,___REF_SYM(62,___S_c_23_var_2d_info),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_info,1,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_stamp,___REF_SYM(73,___S_c_23_var_2d_stamp),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_stamp,1,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_constant,___REF_SYM(60,___S_c_23_var_2d_constant),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_constant,1,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_clone,___REF_SYM(58,___S_c_23_var_2d_clone),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_clone,1,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_temp_3f_,___REF_SYM(75,___S_c_23_var_2d_temp_3f_),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_temp_3f_,1,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_name_2d_set_21_,___REF_SYM(66,___S_c_23_var_2d_name_2d_set_21_),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_name_2d_set_21_,2,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_bound_2d_set_21_,___REF_SYM(55,___S_c_23_var_2d_bound_2d_set_21_),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_bound_2d_set_21_,2,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_refs_2d_set_21_,___REF_SYM(68,___S_c_23_var_2d_refs_2d_set_21_),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_refs_2d_set_21_,2,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_sets_2d_set_21_,___REF_SYM(70,___S_c_23_var_2d_sets_2d_set_21_),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_sets_2d_set_21_,2,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_source_2d_set_21_,___REF_SYM(72,___S_c_23_var_2d_source_2d_set_21_),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_source_2d_set_21_,2,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_boxed_3f__2d_set_21_,___REF_SYM(57,___S_c_23_var_2d_boxed_3f__2d_set_21_),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_boxed_3f__2d_set_21_,2,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_info_2d_set_21_,___REF_SYM(63,___S_c_23_var_2d_info_2d_set_21_),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_info_2d_set_21_,2,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_stamp_2d_set_21_,___REF_SYM(74,___S_c_23_var_2d_stamp_2d_set_21_),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_stamp_2d_set_21_,2,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_constant_2d_set_21_,___REF_SYM(61,___S_c_23_var_2d_constant_2d_set_21_),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_constant_2d_set_21_,2,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_clone_2d_set_21_,___REF_SYM(59,___S_c_23_var_2d_clone_2d_set_21_),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_clone_2d_set_21_,2,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_temp_3f__2d_set_21_,___REF_SYM(76,___S_c_23_var_2d_temp_3f__2d_set_21_),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_temp_3f__2d_set_21_,2,-1,1)
,___DEF_LBL_INTRO(___H_c_23_var_2d_lexical_2d_level,___REF_SYM(64,___S_c_23_var_2d_lexical_2d_level),___REF_FAL,9,0)
,___DEF_LBL_PROC_AT(___H_c_23_var_2d_lexical_2d_level,1,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_var_2d_lexical_2d_level,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_var_2d_lexical_2d_level,___IFD(___RETN,5,0,0x7L),3)
,___DEF_LBL_RET_AT(___H_c_23_var_2d_lexical_2d_level,___IFD(___RETI,0,0,0x3fL),4)
,___DEF_LBL_RET_AT(___H_c_23_var_2d_lexical_2d_level,___IFD(___RETI,0,0,0x3fL),5)
,___DEF_LBL_RET_AT(___H_c_23_var_2d_lexical_2d_level,___IFD(___RETI,8,0,0x3f07L),6)
,___DEF_LBL_RET_AT(___H_c_23_var_2d_lexical_2d_level,___IFD(___RETN,5,0,0x7L),7)
,___DEF_LBL_RET_AT(___H_c_23_var_2d_lexical_2d_level,___IFD(___RETN,5,0,0xdL),8)
,___DEF_LBL_RET_AT(___H_c_23_var_2d_lexical_2d_level,___IFD(___RETN,5,0,0xbL),9)
,___DEF_LBL_INTRO(___H_c_23_make_2d_temp_2d_var,___REF_SYM(47,___S_c_23_make_2d_temp_2d_var),___REF_FAL,6,0)
,___DEF_LBL_PROC_AT(___H_c_23_make_2d_temp_2d_var,1,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_make_2d_temp_2d_var,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_make_2d_temp_2d_var,___IFD(___RETI,8,2,0x3f07L),3)
,___DEF_LBL_RET_AT(___H_c_23_make_2d_temp_2d_var,___IFD(___RETN,5,2,0x7L),4)
,___DEF_LBL_RET_AT(___H_c_23_make_2d_temp_2d_var,___IFD(___RETN,5,3,0xfL),5)
,___DEF_LBL_RET_AT(___H_c_23_make_2d_temp_2d_var,___IFD(___RETI,8,8,0x3f07L),6)
,___DEF_LBL_INTRO(___H_c_23_resize_2d_var_2d_list,___REF_SYM(53,___S_c_23_resize_2d_var_2d_list),___REF_FAL,6,0)
,___DEF_LBL_PROC_AT(___H_c_23_resize_2d_var_2d_list,2,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_resize_2d_var_2d_list,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_resize_2d_var_2d_list,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_RET_AT(___H_c_23_resize_2d_var_2d_list,___IFD(___RETI,0,0,0x3fL),4)
,___DEF_LBL_RET_AT(___H_c_23_resize_2d_var_2d_list,___IFD(___RETI,0,0,0x3fL),5)
,___DEF_LBL_RET_AT(___H_c_23_resize_2d_var_2d_list,___IFD(___RETI,0,0,0x3fL),6)
,___DEF_LBL_INTRO(___H_c_23_env_2d_frame,___REF_SYM(14,___S_c_23_env_2d_frame),___REF_FAL,18,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_frame,2,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame,___IFD(___RETN,5,0,0xfL),3)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame,___IFD(___RETI,1,4,0x3f1L),4)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame,___IFD(___RETI,1,4,0x3f1L),5)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame,___IFD(___RETI,1,4,0x3f1L),6)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame,___IFD(___RETI,0,0,0x3fL),7)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame,___IFD(___RETI,1,4,0x3f1L),8)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame,___IFD(___RETI,8,1,0x3f0fL),9)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame,___IFD(___RETN,5,1,0xfL),10)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame,___IFD(___RETI,0,0,0x3fL),11)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame,___IFD(___RETI,8,0,0x3f07L),12)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame,___IFD(___RETN,5,0,0x7L),13)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame,___IFD(___RETN,5,0,0x7L),14)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame,___IFD(___RETI,0,0,0x3fL),15)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame,___IFD(___RETI,0,0,0x3fL),16)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame,___IFD(___RETI,8,0,0x3f1fL),17)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame,___IFD(___RETN,5,0,0x1fL),18)
,___DEF_LBL_INTRO(___H_c_23_env_2d_new_2d_var_21_,___REF_SYM(30,___S_c_23_env_2d_new_2d_var_21_),___REF_FAL,11,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_new_2d_var_21_,3,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_new_2d_var_21_,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_new_2d_var_21_,___OFD(___RETI,12,1,0x3f03fL),3)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_new_2d_var_21_,___IFD(___RETN,9,1,0x3fL),4)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_new_2d_var_21_,___IFD(___RETN,9,1,0x7fL),5)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_new_2d_var_21_,___IFD(___RETN,9,1,0xffL),6)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_new_2d_var_21_,___OFD(___RETI,12,1,0x3f0ffL),7)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_new_2d_var_21_,___OFD(___RETI,12,1,0x3f02aL),8)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_new_2d_var_21_,___IFD(___RETN,5,1,0x7L),9)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_new_2d_var_21_,___IFD(___RETI,8,1,0x3f02L),10)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_new_2d_var_21_,___IFD(___RETI,2,1,0x3f2L),11)
,___DEF_LBL_INTRO(___H_c_23_env_2d_macro,___REF_SYM(22,___S_c_23_env_2d_macro),___REF_FAL,8,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_macro,3,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_macro,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_macro,___IFD(___RETI,8,0,0x3f0fL),3)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_macro,___IFD(___RETN,5,0,0xfL),4)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_macro,___IFD(___RETN,5,0,0xfL),5)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_macro,___IFD(___RETI,8,0,0x3f0bL),6)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_macro,___IFD(___RETI,8,8,0x3f00L),7)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_macro,___IFD(___RETI,8,8,0x3f00L),8)
,___DEF_LBL_INTRO(___H_c_23_env_2d_macros_2d_set,___REF_SYM(24,___S_c_23_env_2d_macros_2d_set),___REF_FAL,4,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_macros_2d_set,2,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_macros_2d_set,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_macros_2d_set,___IFD(___RETI,2,4,0x3f3L),3)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_macros_2d_set,___IFD(___RETI,0,0,0x3fL),4)
,___DEF_LBL_INTRO(___H_c_23_env_2d_declare,___REF_SYM(11,___S_c_23_env_2d_declare),___REF_FAL,4,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_declare,2,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_declare,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_declare,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_declare,___IFD(___RETI,0,0,0x3fL),4)
,___DEF_LBL_INTRO(___H_c_23_env_2d_decl_2d_set,___REF_SYM(10,___S_c_23_env_2d_decl_2d_set),___REF_FAL,4,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_decl_2d_set,2,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_decl_2d_set,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_decl_2d_set,___IFD(___RETI,2,4,0x3f3L),3)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_decl_2d_set,___IFD(___RETI,0,0,0x3fL),4)
,___DEF_LBL_INTRO(___H_c_23_env_2d_namespace,___REF_SYM(25,___S_c_23_env_2d_namespace),___REF_FAL,4,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_namespace,2,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace,___IFD(___RETI,0,0,0x3fL),4)
,___DEF_LBL_INTRO(___H_c_23_env_2d_namespace_2d_set,___REF_SYM(29,___S_c_23_env_2d_namespace_2d_set),___REF_FAL,4,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_namespace_2d_set,2,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_set,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_set,___IFD(___RETI,2,4,0x3f3L),3)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_set,___IFD(___RETI,0,0,0x3fL),4)
,___DEF_LBL_INTRO(___H_c_23_env_2d_vars_2d_ref,___REF_SYM(32,___S_c_23_env_2d_vars_2d_ref),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_vars_2d_ref,1,-1,1)
,___DEF_LBL_INTRO(___H_c_23_env_2d_macros_2d_ref,___REF_SYM(23,___S_c_23_env_2d_macros_2d_ref),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_macros_2d_ref,1,-1,1)
,___DEF_LBL_INTRO(___H_c_23_env_2d_decl_2d_ref,___REF_SYM(9,___S_c_23_env_2d_decl_2d_ref),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_decl_2d_ref,1,-1,1)
,___DEF_LBL_INTRO(___H_c_23_env_2d_namespace_2d_ref,___REF_SYM(28,___S_c_23_env_2d_namespace_2d_ref),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_namespace_2d_ref,1,-1,1)
,___DEF_LBL_INTRO(___H_c_23_env_2d_parent_2d_ref,___REF_SYM(31,___S_c_23_env_2d_parent_2d_ref),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_parent_2d_ref,1,-1,1)
,___DEF_LBL_INTRO(___H_c_23_env_2d_externals_2d_ref,___REF_SYM(13,___S_c_23_env_2d_externals_2d_ref),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_externals_2d_ref,1,-1,1)
,___DEF_LBL_INTRO(___H_c_23_env_2d_frame_2d_lookup_2d_var,___REF_SYM(15,___S_c_23_env_2d_frame_2d_lookup_2d_var),___REF_FAL,5,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_frame_2d_lookup_2d_var,2,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame_2d_lookup_2d_var,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame_2d_lookup_2d_var,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame_2d_lookup_2d_var,___IFD(___RETI,0,0,0x3fL),4)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_frame_2d_lookup_2d_var,___IFD(___RETI,0,0,0x3fL),5)
,___DEF_LBL_INTRO(___H_c_23_env_2d_namespace_2d_lookup,___REF_SYM(26,___S_c_23_env_2d_namespace_2d_lookup),___REF_FAL,10,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_namespace_2d_lookup,2,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup,___IFD(___RETN,5,0,0xfL),4)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup,___IFD(___RETI,0,0,0x3fL),5)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup,___IFD(___RETI,0,0,0x3fL),6)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup,___IFD(___RETI,0,0,0x3fL),7)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup,___IFD(___RETI,8,0,0x3f0fL),8)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup,___IFD(___RETI,0,0,0x3fL),9)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup,___IFD(___RETI,8,8,0x3f00L),10)
,___DEF_LBL_INTRO(___H_c_23_env_2d_namespace_2d_lookup_2d_both,___REF_SYM(27,___S_c_23_env_2d_namespace_2d_lookup_2d_both),___REF_FAL,17,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_namespace_2d_lookup_2d_both,2,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup_2d_both,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup_2d_both,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup_2d_both,___IFD(___RETN,9,1,0x3eL),4)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup_2d_both,___IFD(___RETI,0,0,0x3fL),5)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup_2d_both,___IFD(___RETI,0,0,0x3fL),6)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup_2d_both,___IFD(___RETI,1,4,0x3f0L),7)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup_2d_both,___IFD(___RETI,8,0,0x3f03L),8)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup_2d_both,___IFD(___RETN,5,0,0x3L),9)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup_2d_both,___IFD(___RETI,8,0,0x3f03L),10)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup_2d_both,___IFD(___RETI,1,0,0x3f1L),11)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup_2d_both,___IFD(___RETI,1,4,0x3f1L),12)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup_2d_both,___OFD(___RETI,12,1,0x3f03eL),13)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup_2d_both,___IFD(___RETI,0,0,0x3fL),14)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup_2d_both,___IFD(___RETN,5,1,0x12L),15)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup_2d_both,___IFD(___RETI,8,1,0x3f12L),16)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_namespace_2d_lookup_2d_both,___IFD(___RETI,2,1,0x3f2L),17)
,___DEF_LBL_INTRO(___H_c_23_macro_2d_list_2d_cached,___REF_SYM(37,___S_c_23_macro_2d_list_2d_cached),___REF_FAL,2,0)
,___DEF_LBL_PROC_AT(___H_c_23_macro_2d_list_2d_cached,1,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_cached,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_INTRO(___H_c_23_macro_2d_list_2d_empty,___REF_SYM(38,___S_c_23_macro_2d_list_2d_empty),___REF_FAL,2,0)
,___DEF_LBL_PROC_AT(___H_c_23_macro_2d_list_2d_empty,0,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_empty,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_INTRO(___H_c_23_macro_2d_list_2d_ref,___REF_SYM(43,___S_c_23_macro_2d_list_2d_ref),___REF_FAL,8,0)
,___DEF_LBL_PROC_AT(___H_c_23_macro_2d_list_2d_ref,2,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_ref,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_ref,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_ref,___IFD(___RETN,5,0,0x7L),4)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_ref,___IFD(___RETI,0,0,0x3fL),5)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_ref,___IFD(___RETI,0,0,0x3fL),6)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_ref,___IFD(___RETI,8,0,0x3f07L),7)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_ref,___IFD(___RETI,8,8,0x3f00L),8)
,___DEF_LBL_INTRO(___H_c_23_macro_2d_list_2d_flatten,___REF_SYM(40,___S_c_23_macro_2d_list_2d_flatten),___REF_FAL,19,0)
,___DEF_LBL_PROC_AT(___H_c_23_macro_2d_list_2d_flatten,1,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_flatten,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_flatten,___IFD(___RETI,8,0,0x3f03L),3)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_flatten,___IFD(___RETN,5,0,0x3L),4)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_flatten,___IFD(___RETN,5,0,0x7L),5)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_flatten,___IFD(___RETI,0,0,0x3fL),6)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_flatten,___IFD(___RETI,0,0,0x3fL),7)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_flatten,___IFD(___RETI,8,0,0x3f07L),8)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_flatten,___IFD(___RETN,5,0,0x7L),9)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_flatten,___IFD(___RETI,8,0,0x3f07L),10)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_flatten,___IFD(___RETI,4,4,0x3f0L),11)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_flatten,___IFD(___RETI,4,4,0x3f0L),12)
,___DEF_LBL_PROC_AT(___H_c_23_macro_2d_list_2d_flatten,2,1,13)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_flatten,___IFD(___RETI,0,0,0x3fL),14)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_flatten,___IFD(___RETI,8,0,0x3f0fL),15)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_flatten,___IFD(___RETN,5,0,0xfL),16)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_flatten,___IFD(___RETI,8,8,0x3f00L),17)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_flatten,___IFD(___RETN,5,0,0xfL),18)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_flatten,___IFD(___RETN,5,0,0x5L),19)
,___DEF_LBL_INTRO(___H_c_23_macro_2d_list_2d_extend,___REF_SYM(39,___S_c_23_macro_2d_list_2d_extend),___REF_FAL,8,0)
,___DEF_LBL_PROC_AT(___H_c_23_macro_2d_list_2d_extend,3,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_extend,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_extend,___IFD(___RETI,8,0,0x3f0fL),3)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_extend,___IFD(___RETN,5,0,0xfL),4)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_extend,___IFD(___RETN,5,0,0x7L),5)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_extend,___IFD(___RETN,5,0,0x9L),6)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_extend,___IFD(___RETI,8,0,0x3f0fL),7)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_extend,___IFD(___RETI,1,0,0x3f1L),8)
,___DEF_LBL_INTRO(___H_c_23_macro_2d_list_2d_prefix_2d_length,___REF_SYM(42,___S_c_23_macro_2d_list_2d_prefix_2d_length),___REF_FAL,7,0)
,___DEF_LBL_PROC_AT(___H_c_23_macro_2d_list_2d_prefix_2d_length,2,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_prefix_2d_length,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_prefix_2d_length,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_prefix_2d_length,___IFD(___RETN,5,0,0xfL),4)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_prefix_2d_length,___IFD(___RETI,0,0,0x3fL),5)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_prefix_2d_length,___IFD(___RETI,0,0,0x3fL),6)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_prefix_2d_length,___IFD(___RETI,8,0,0x3f0fL),7)
,___DEF_LBL_INTRO(___H_c_23_macro_2d_list_2d_suffix,___REF_SYM(44,___S_c_23_macro_2d_list_2d_suffix),___REF_FAL,2,0)
,___DEF_LBL_PROC_AT(___H_c_23_macro_2d_list_2d_suffix,2,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_suffix,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_INTRO(___H_c_23_macro_2d_list_2d_overlay_2d_prefix,___REF_SYM(41,___S_c_23_macro_2d_list_2d_overlay_2d_prefix),___REF_FAL,5,0)
,___DEF_LBL_PROC_AT(___H_c_23_macro_2d_list_2d_overlay_2d_prefix,3,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_overlay_2d_prefix,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_overlay_2d_prefix,___IFD(___RETI,8,0,0x3f03L),3)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_overlay_2d_prefix,___IFD(___RETN,5,0,0x3L),4)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_overlay_2d_prefix,___IFD(___RETI,8,8,0x3f00L),5)
,___DEF_LBL_INTRO(___H_c_23_macro_2d_list_2d_table,___REF_SYM(45,___S_c_23_macro_2d_list_2d_table),___REF_FAL,17,0)
,___DEF_LBL_PROC_AT(___H_c_23_macro_2d_list_2d_table,1,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_table,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_table,___IFD(___RETI,8,0,0x3f03L),3)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_table,___IFD(___RETN,5,0,0x3L),4)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_table,___IFD(___RETN,5,0,0x3L),5)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_table,___IFD(___RETN,5,0,0x7L),6)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_table,___IFD(___RETN,5,0,0x7L),7)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_table,___IFD(___RETN,5,0,0x7L),8)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_table,___IFD(___RETN,5,0,0x3L),9)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_table,___IFD(___RETN,5,0,0x5L),10)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_table,___IFD(___RETN,5,0,0x3L),11)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_table,___IFD(___RETN,5,0,0x7L),12)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_table,___IFD(___RETI,0,0,0x3fL),13)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_table,___IFD(___RETI,0,0,0x3fL),14)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_table,___IFD(___RETI,8,0,0x3f0fL),15)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_table,___IFD(___RETN,5,0,0xfL),16)
,___DEF_LBL_RET_AT(___H_c_23_macro_2d_list_2d_table,___IFD(___RETN,5,0,0x7L),17)
,___DEF_LBL_INTRO(___H_c_23_env_2d_lookup,___REF_SYM(18,___S_c_23_env_2d_lookup),___REF_FAL,20,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_lookup,4,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup,___IFD(___RETI,1,4,0x3f1L),2)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup,___IFD(___RETI,8,3,0x3f1fL),3)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup,___IFD(___RETN,5,3,0x1fL),4)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup,___IFD(___RETI,2,4,0x3f3L),5)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup,___IFD(___RETN,9,2,0x3fL),6)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup,___IFD(___RETI,2,4,0x3f3L),7)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup,___IFD(___RETI,2,4,0x3f3L),8)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup,___IFD(___RETI,2,4,0x3f3L),9)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup,___OFD(___RETI,12,2,0x3f03fL),10)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup,___IFD(___RETN,9,2,0x3fL),11)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup,___IFD(___RETN,9,2,0x3fL),12)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup,___OFD(___RETI,12,12,0x3f002L),13)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup,___OFD(___RETI,12,12,0x3f002L),14)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup,___IFD(___RETI,2,4,0x3f3L),15)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup,___IFD(___RETI,8,2,0x3f1fL),16)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup,___IFD(___RETN,5,2,0x1fL),17)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup,___IFD(___RETI,2,4,0x3f3L),18)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup,___IFD(___RETN,5,2,0x1fL),19)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup,___IFD(___RETI,2,4,0x3f3L),20)
,___DEF_LBL_INTRO(___H_c_23_namespace_2d_valid_3f_,___REF_SYM(51,___S_c_23_namespace_2d_valid_3f_),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_namespace_2d_valid_3f_,1,-1,1)
,___DEF_LBL_INTRO(___H_c_23_full_2d_name_3f_,___REF_SYM(36,___S_c_23_full_2d_name_3f_),___REF_FAL,6,0)
,___DEF_LBL_PROC_AT(___H_c_23_full_2d_name_3f_,1,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_full_2d_name_3f_,___IFD(___RETN,1,0,0x1L),2)
,___DEF_LBL_RET_AT(___H_c_23_full_2d_name_3f_,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_RET_AT(___H_c_23_full_2d_name_3f_,___IFD(___RETI,0,0,0x3fL),4)
,___DEF_LBL_RET_AT(___H_c_23_full_2d_name_3f_,___IFD(___RETI,0,0,0x3fL),5)
,___DEF_LBL_RET_AT(___H_c_23_full_2d_name_3f_,___IFD(___RETI,0,0,0x3fL),6)
,___DEF_LBL_INTRO(___H_c_23_make_2d_full_2d_name,___REF_SYM(46,___S_c_23_make_2d_full_2d_name),___REF_FAL,7,0)
,___DEF_LBL_PROC_AT(___H_c_23_make_2d_full_2d_name,2,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_make_2d_full_2d_name,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_make_2d_full_2d_name,___IFD(___RETI,1,0,0x3f1L),3)
,___DEF_LBL_RET_AT(___H_c_23_make_2d_full_2d_name,___IFD(___RETN,5,0,0x3L),4)
,___DEF_LBL_RET_AT(___H_c_23_make_2d_full_2d_name,___IFD(___RETI,1,0,0x3f1L),5)
,___DEF_LBL_RET_AT(___H_c_23_make_2d_full_2d_name,___IFD(___RETN,1,0,0x1L),6)
,___DEF_LBL_RET_AT(___H_c_23_make_2d_full_2d_name,___IFD(___RETI,4,4,0x3f0L),7)
,___DEF_LBL_INTRO(___H_c_23_env_2d_lookup_2d_var,___REF_SYM(21,___S_c_23_env_2d_lookup_2d_var),___REF_FAL,11,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_lookup_2d_var,3,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup_2d_var,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup_2d_var,___IFD(___RETI,1,4,0x3f1L),3)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup_2d_var,___IFD(___RETI,2,4,0x3f1L),4)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup_2d_var,___IFD(___RETI,2,4,0x3f1L),5)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_lookup_2d_var,3,1,6)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup_2d_var,___IFD(___RETI,0,0,0x3fL),7)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup_2d_var,___IFD(___RETI,8,0,0x3f07L),8)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup_2d_var,___IFD(___RETN,5,0,0x7L),9)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup_2d_var,___IFD(___RETI,8,8,0x3f00L),10)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup_2d_var,___IFD(___RETI,0,0,0x3fL),11)
,___DEF_LBL_INTRO(___H_c_23_env_2d_define_2d_var,___REF_SYM(12,___S_c_23_env_2d_define_2d_var),___REF_FAL,12,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_define_2d_var,3,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_define_2d_var,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_define_2d_var,___IFD(___RETI,1,4,0x3f1L),3)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_define_2d_var,___IFD(___RETI,2,4,0x3f1L),4)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_define_2d_var,___IFD(___RETI,2,4,0x3f1L),5)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_define_2d_var,3,1,6)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_define_2d_var,___IFD(___RETI,0,0,0x3fL),7)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_define_2d_var,___IFD(___RETI,8,0,0x3f07L),8)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_define_2d_var,___IFD(___RETN,5,0,0x7L),9)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_define_2d_var,___IFD(___RETI,8,8,0x3f00L),10)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_define_2d_var,___IFD(___RETI,8,8,0x3f00L),11)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_define_2d_var,___IFD(___RETI,0,0,0x3fL),12)
,___DEF_LBL_INTRO(___H_c_23_env_2d_lookup_2d_global_2d_var,___REF_SYM(19,___S_c_23_env_2d_lookup_2d_global_2d_var),___REF_FAL,6,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_lookup_2d_global_2d_var,2,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup_2d_global_2d_var,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup_2d_global_2d_var,___IFD(___RETI,8,0,0x3f03L),3)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup_2d_global_2d_var,___IFD(___RETN,5,0,0x3L),4)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup_2d_global_2d_var,___IFD(___RETN,5,0,0x7L),5)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup_2d_global_2d_var,___IFD(___RETI,8,8,0x3f00L),6)
,___DEF_LBL_INTRO(___H_c_23_env_2d_global_2d_variables,___REF_SYM(17,___S_c_23_env_2d_global_2d_variables),___REF_FAL,4,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_global_2d_variables,1,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_global_2d_variables,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_global_2d_variables,___IFD(___RETI,4,0,0x3f1L),3)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_global_2d_variables,___IFD(___RETN,1,0,0x1L),4)
,___DEF_LBL_INTRO(___H_c_23_env_2d_global_2d_env,___REF_SYM(16,___S_c_23_env_2d_global_2d_env),___REF_FAL,3,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_global_2d_env,1,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_global_2d_env,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_global_2d_env,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_INTRO(___H_c_23_env_2d_lookup_2d_macro,___REF_SYM(20,___S_c_23_env_2d_lookup_2d_macro),___REF_FAL,7,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_lookup_2d_macro,2,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup_2d_macro,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup_2d_macro,___IFD(___RETI,1,4,0x3f1L),3)
,___DEF_LBL_PROC_AT(___H_c_23_env_2d_lookup_2d_macro,3,-1,4)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup_2d_macro,___IFD(___RETI,0,0,0x3fL),5)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup_2d_macro,___IFD(___RETI,8,0,0x3f03L),6)
,___DEF_LBL_RET_AT(___H_c_23_env_2d_lookup_2d_macro,___IFD(___RETN,5,0,0x3L),7)
,___DEF_LBL_INTRO(___H_c_23_define_2d_flag_2d_decl,___REF_SYM(5,___S_c_23_define_2d_flag_2d_decl),___REF_FAL,3,0)
,___DEF_LBL_PROC_AT(___H_c_23_define_2d_flag_2d_decl,2,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_define_2d_flag_2d_decl,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_define_2d_flag_2d_decl,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_INTRO(___H_c_23_define_2d_parameterized_2d_decl,___REF_SYM(8,___S_c_23_define_2d_parameterized_2d_decl),___REF_FAL,3,0)
,___DEF_LBL_PROC_AT(___H_c_23_define_2d_parameterized_2d_decl,2,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_define_2d_parameterized_2d_decl,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_define_2d_parameterized_2d_decl,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_INTRO(___H_c_23_define_2d_boolean_2d_decl,___REF_SYM(4,___S_c_23_define_2d_boolean_2d_decl),___REF_FAL,3,0)
,___DEF_LBL_PROC_AT(___H_c_23_define_2d_boolean_2d_decl,1,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_define_2d_boolean_2d_decl,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_define_2d_boolean_2d_decl,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_INTRO(___H_c_23_define_2d_namable_2d_decl,___REF_SYM(7,___S_c_23_define_2d_namable_2d_decl),___REF_FAL,3,0)
,___DEF_LBL_PROC_AT(___H_c_23_define_2d_namable_2d_decl,2,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_define_2d_namable_2d_decl,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_define_2d_namable_2d_decl,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_INTRO(___H_c_23_define_2d_namable_2d_boolean_2d_decl,___REF_SYM(6,___S_c_23_define_2d_namable_2d_boolean_2d_decl),___REF_FAL,3,0)
,___DEF_LBL_PROC_AT(___H_c_23_define_2d_namable_2d_boolean_2d_decl,1,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_define_2d_namable_2d_boolean_2d_decl,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_define_2d_namable_2d_boolean_2d_decl,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_INTRO(___H_c_23_flag_2d_decl,___REF_SYM(35,___S_c_23_flag_2d_decl),___REF_FAL,3,0)
,___DEF_LBL_PROC_AT(___H_c_23_flag_2d_decl,3,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_flag_2d_decl,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_flag_2d_decl,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_INTRO(___H_c_23_parameterized_2d_decl,___REF_SYM(52,___S_c_23_parameterized_2d_decl),___REF_FAL,3,0)
,___DEF_LBL_PROC_AT(___H_c_23_parameterized_2d_decl,3,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_parameterized_2d_decl,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_parameterized_2d_decl,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_INTRO(___H_c_23_boolean_2d_decl,___REF_SYM(2,___S_c_23_boolean_2d_decl),___REF_FAL,3,0)
,___DEF_LBL_PROC_AT(___H_c_23_boolean_2d_decl,3,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_boolean_2d_decl,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_boolean_2d_decl,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_INTRO(___H_c_23_namable_2d_decl,___REF_SYM(50,___S_c_23_namable_2d_decl),___REF_FAL,3,0)
,___DEF_LBL_PROC_AT(___H_c_23_namable_2d_decl,4,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_namable_2d_decl,___IFD(___RETI,1,4,0x3f0L),2)
,___DEF_LBL_RET_AT(___H_c_23_namable_2d_decl,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_INTRO(___H_c_23_namable_2d_boolean_2d_decl,___REF_SYM(49,___S_c_23_namable_2d_boolean_2d_decl),___REF_FAL,3,0)
,___DEF_LBL_PROC_AT(___H_c_23_namable_2d_boolean_2d_decl,4,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_namable_2d_boolean_2d_decl,___IFD(___RETI,1,4,0x3f0L),2)
,___DEF_LBL_RET_AT(___H_c_23_namable_2d_boolean_2d_decl,___IFD(___RETI,0,0,0x3fL),3)
,___DEF_LBL_INTRO(___H_c_23_declaration_2d_value,___REF_SYM(3,___S_c_23_declaration_2d_value),___REF_FAL,8,0)
,___DEF_LBL_PROC_AT(___H_c_23_declaration_2d_value,4,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_declaration_2d_value,___IFD(___RETI,1,4,0x3f1L),2)
,___DEF_LBL_RET_AT(___H_c_23_declaration_2d_value,___IFD(___RETN,9,2,0x7dL),3)
,___DEF_LBL_RET_AT(___H_c_23_declaration_2d_value,___IFD(___RETI,1,4,0x3f1L),4)
,___DEF_LBL_RET_AT(___H_c_23_declaration_2d_value,___IFD(___RETI,1,4,0x3f1L),5)
,___DEF_LBL_RET_AT(___H_c_23_declaration_2d_value,___IFD(___RETI,2,4,0x3f1L),6)
,___DEF_LBL_RET_AT(___H_c_23_declaration_2d_value,___OFD(___RETI,12,2,0x3f07dL),7)
,___DEF_LBL_RET_AT(___H_c_23_declaration_2d_value,___IFD(___RETI,0,0,0x3fL),8)
,___DEF_LBL_INTRO(___H_c_23_env_2e_begin_21_,___REF_SYM(33,___S_c_23_env_2e_begin_21_),___REF_FAL,8,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2e_begin_21_,0,-1,1)
,___DEF_LBL_RET_AT(___H_c_23_env_2e_begin_21_,___IFD(___RETI,0,0,0x3fL),2)
,___DEF_LBL_RET_AT(___H_c_23_env_2e_begin_21_,___IFD(___RETI,4,0,0x3f1L),3)
,___DEF_LBL_RET_AT(___H_c_23_env_2e_begin_21_,___IFD(___RETN,1,0,0x1L),4)
,___DEF_LBL_RET_AT(___H_c_23_env_2e_begin_21_,___IFD(___RETN,1,0,0x1L),5)
,___DEF_LBL_RET_AT(___H_c_23_env_2e_begin_21_,___IFD(___RETN,1,0,0x1L),6)
,___DEF_LBL_RET_AT(___H_c_23_env_2e_begin_21_,___IFD(___RETN,1,0,0x1L),7)
,___DEF_LBL_RET_AT(___H_c_23_env_2e_begin_21_,___IFD(___RETN,1,0,0x1L),8)
,___DEF_LBL_INTRO(___H_c_23_env_2e_end_21_,___REF_SYM(34,___S_c_23_env_2e_end_21_),___REF_FAL,1,0)
,___DEF_LBL_PROC_AT(___H_c_23_env_2e_end_21_,0,-1,1)
___END_LBL

___BEGIN_OFD
 ___DEF_OFD(___RETI,12,3)
               ___GCMAP1(0x3f07fL)
,___DEF_OFD(___RETI,12,3)
               ___GCMAP1(0x3f07fL)
,___DEF_OFD(___RETI,12,1)
               ___GCMAP1(0x3f03fL)
,___DEF_OFD(___RETI,12,1)
               ___GCMAP1(0x3f0ffL)
,___DEF_OFD(___RETI,12,1)
               ___GCMAP1(0x3f02aL)
,___DEF_OFD(___RETI,12,1)
               ___GCMAP1(0x3f03eL)
,___DEF_OFD(___RETI,12,2)
               ___GCMAP1(0x3f03fL)
,___DEF_OFD(___RETI,12,12)
               ___GCMAP1(0x3f002L)
,___DEF_OFD(___RETI,12,12)
               ___GCMAP1(0x3f002L)
,___DEF_OFD(___RETI,12,2)
               ___GCMAP1(0x3f07dL)
___END_OFD

___BEGIN_MOD_PRM
___DEF_MOD_PRM(0,___G___env_23_,1)
___DEF_MOD_PRM(55,___G_c_23_make_2d_var,11)
___DEF_MOD_PRM(91,___G_c_23_var_3f_,18)
___DEF_MOD_PRM(78,___G_c_23_var_2d_name,20)
___DEF_MOD_PRM(67,___G_c_23_var_2d_bound,22)
___DEF_MOD_PRM(80,___G_c_23_var_2d_refs,24)
___DEF_MOD_PRM(82,___G_c_23_var_2d_sets,26)
___DEF_MOD_PRM(84,___G_c_23_var_2d_source,28)
___DEF_MOD_PRM(69,___G_c_23_var_2d_boxed_3f_,30)
___DEF_MOD_PRM(75,___G_c_23_var_2d_info,32)
___DEF_MOD_PRM(86,___G_c_23_var_2d_stamp,34)
___DEF_MOD_PRM(73,___G_c_23_var_2d_constant,36)
___DEF_MOD_PRM(71,___G_c_23_var_2d_clone,38)
___DEF_MOD_PRM(89,___G_c_23_var_2d_temp_3f_,40)
___DEF_MOD_PRM(79,___G_c_23_var_2d_name_2d_set_21_,42)
___DEF_MOD_PRM(68,___G_c_23_var_2d_bound_2d_set_21_,44)
___DEF_MOD_PRM(81,___G_c_23_var_2d_refs_2d_set_21_,46)
___DEF_MOD_PRM(83,___G_c_23_var_2d_sets_2d_set_21_,48)
___DEF_MOD_PRM(85,___G_c_23_var_2d_source_2d_set_21_,50)
___DEF_MOD_PRM(70,___G_c_23_var_2d_boxed_3f__2d_set_21_,52)
___DEF_MOD_PRM(76,___G_c_23_var_2d_info_2d_set_21_,54)
___DEF_MOD_PRM(87,___G_c_23_var_2d_stamp_2d_set_21_,56)
___DEF_MOD_PRM(74,___G_c_23_var_2d_constant_2d_set_21_,58)
___DEF_MOD_PRM(72,___G_c_23_var_2d_clone_2d_set_21_,60)
___DEF_MOD_PRM(90,___G_c_23_var_2d_temp_3f__2d_set_21_,62)
___DEF_MOD_PRM(77,___G_c_23_var_2d_lexical_2d_level,64)
___DEF_MOD_PRM(54,___G_c_23_make_2d_temp_2d_var,74)
___DEF_MOD_PRM(64,___G_c_23_resize_2d_var_2d_list,81)
___DEF_MOD_PRM(16,___G_c_23_env_2d_frame,88)
___DEF_MOD_PRM(32,___G_c_23_env_2d_new_2d_var_21_,107)
___DEF_MOD_PRM(24,___G_c_23_env_2d_macro,119)
___DEF_MOD_PRM(26,___G_c_23_env_2d_macros_2d_set,128)
___DEF_MOD_PRM(13,___G_c_23_env_2d_declare,133)
___DEF_MOD_PRM(12,___G_c_23_env_2d_decl_2d_set,138)
___DEF_MOD_PRM(27,___G_c_23_env_2d_namespace,143)
___DEF_MOD_PRM(31,___G_c_23_env_2d_namespace_2d_set,148)
___DEF_MOD_PRM(34,___G_c_23_env_2d_vars_2d_ref,153)
___DEF_MOD_PRM(25,___G_c_23_env_2d_macros_2d_ref,155)
___DEF_MOD_PRM(11,___G_c_23_env_2d_decl_2d_ref,157)
___DEF_MOD_PRM(30,___G_c_23_env_2d_namespace_2d_ref,159)
___DEF_MOD_PRM(33,___G_c_23_env_2d_parent_2d_ref,161)
___DEF_MOD_PRM(15,___G_c_23_env_2d_externals_2d_ref,163)
___DEF_MOD_PRM(17,___G_c_23_env_2d_frame_2d_lookup_2d_var,165)
___DEF_MOD_PRM(28,___G_c_23_env_2d_namespace_2d_lookup,171)
___DEF_MOD_PRM(29,___G_c_23_env_2d_namespace_2d_lookup_2d_both,182)
___DEF_MOD_PRM(41,___G_c_23_macro_2d_list_2d_cached,200)
___DEF_MOD_PRM(42,___G_c_23_macro_2d_list_2d_empty,203)
___DEF_MOD_PRM(48,___G_c_23_macro_2d_list_2d_ref,206)
___DEF_MOD_PRM(44,___G_c_23_macro_2d_list_2d_flatten,215)
___DEF_MOD_PRM(43,___G_c_23_macro_2d_list_2d_extend,235)
___DEF_MOD_PRM(47,___G_c_23_macro_2d_list_2d_prefix_2d_length,244)
___DEF_MOD_PRM(49,___G_c_23_macro_2d_list_2d_suffix,252)
___DEF_MOD_PRM(46,___G_c_23_macro_2d_list_2d_overlay_2d_prefix,255)
___DEF_MOD_PRM(50,___G_c_23_macro_2d_list_2d_table,261)
___DEF_MOD_PRM(20,___G_c_23_env_2d_lookup,279)
___DEF_MOD_PRM(60,___G_c_23_namespace_2d_valid_3f_,300)
___DEF_MOD_PRM(39,___G_c_23_full_2d_name_3f_,302)
___DEF_MOD_PRM(52,___G_c_23_make_2d_full_2d_name,309)
___DEF_MOD_PRM(23,___G_c_23_env_2d_lookup_2d_var,317)
___DEF_MOD_PRM(14,___G_c_23_env_2d_define_2d_var,329)
___DEF_MOD_PRM(21,___G_c_23_env_2d_lookup_2d_global_2d_var,342)
___DEF_MOD_PRM(19,___G_c_23_env_2d_global_2d_variables,349)
___DEF_MOD_PRM(18,___G_c_23_env_2d_global_2d_env,354)
___DEF_MOD_PRM(22,___G_c_23_env_2d_lookup_2d_macro,358)
___DEF_MOD_PRM(6,___G_c_23_define_2d_flag_2d_decl,366)
___DEF_MOD_PRM(9,___G_c_23_define_2d_parameterized_2d_decl,370)
___DEF_MOD_PRM(5,___G_c_23_define_2d_boolean_2d_decl,374)
___DEF_MOD_PRM(8,___G_c_23_define_2d_namable_2d_decl,378)
___DEF_MOD_PRM(7,___G_c_23_define_2d_namable_2d_boolean_2d_decl,382)
___DEF_MOD_PRM(37,___G_c_23_flag_2d_decl,386)
___DEF_MOD_PRM(62,___G_c_23_parameterized_2d_decl,390)
___DEF_MOD_PRM(1,___G_c_23_boolean_2d_decl,394)
___DEF_MOD_PRM(58,___G_c_23_namable_2d_decl,398)
___DEF_MOD_PRM(56,___G_c_23_namable_2d_boolean_2d_decl,402)
___DEF_MOD_PRM(4,___G_c_23_declaration_2d_value,406)
___DEF_MOD_PRM(35,___G_c_23_env_2e_begin_21_,415)
___DEF_MOD_PRM(36,___G_c_23_env_2e_end_21_,424)
___END_MOD_PRM

___BEGIN_MOD_C_INIT
___END_MOD_C_INIT

___BEGIN_MOD_GLO
___DEF_MOD_GLO(0,___G___env_23_,1)
___DEF_MOD_GLO(55,___G_c_23_make_2d_var,11)
___DEF_MOD_GLO(91,___G_c_23_var_3f_,18)
___DEF_MOD_GLO(78,___G_c_23_var_2d_name,20)
___DEF_MOD_GLO(67,___G_c_23_var_2d_bound,22)
___DEF_MOD_GLO(80,___G_c_23_var_2d_refs,24)
___DEF_MOD_GLO(82,___G_c_23_var_2d_sets,26)
___DEF_MOD_GLO(84,___G_c_23_var_2d_source,28)
___DEF_MOD_GLO(69,___G_c_23_var_2d_boxed_3f_,30)
___DEF_MOD_GLO(75,___G_c_23_var_2d_info,32)
___DEF_MOD_GLO(86,___G_c_23_var_2d_stamp,34)
___DEF_MOD_GLO(73,___G_c_23_var_2d_constant,36)
___DEF_MOD_GLO(71,___G_c_23_var_2d_clone,38)
___DEF_MOD_GLO(89,___G_c_23_var_2d_temp_3f_,40)
___DEF_MOD_GLO(79,___G_c_23_var_2d_name_2d_set_21_,42)
___DEF_MOD_GLO(68,___G_c_23_var_2d_bound_2d_set_21_,44)
___DEF_MOD_GLO(81,___G_c_23_var_2d_refs_2d_set_21_,46)
___DEF_MOD_GLO(83,___G_c_23_var_2d_sets_2d_set_21_,48)
___DEF_MOD_GLO(85,___G_c_23_var_2d_source_2d_set_21_,50)
___DEF_MOD_GLO(70,___G_c_23_var_2d_boxed_3f__2d_set_21_,52)
___DEF_MOD_GLO(76,___G_c_23_var_2d_info_2d_set_21_,54)
___DEF_MOD_GLO(87,___G_c_23_var_2d_stamp_2d_set_21_,56)
___DEF_MOD_GLO(74,___G_c_23_var_2d_constant_2d_set_21_,58)
___DEF_MOD_GLO(72,___G_c_23_var_2d_clone_2d_set_21_,60)
___DEF_MOD_GLO(90,___G_c_23_var_2d_temp_3f__2d_set_21_,62)
___DEF_MOD_GLO(77,___G_c_23_var_2d_lexical_2d_level,64)
___DEF_MOD_GLO(54,___G_c_23_make_2d_temp_2d_var,74)
___DEF_MOD_GLO(64,___G_c_23_resize_2d_var_2d_list,81)
___DEF_MOD_GLO(16,___G_c_23_env_2d_frame,88)
___DEF_MOD_GLO(32,___G_c_23_env_2d_new_2d_var_21_,107)
___DEF_MOD_GLO(24,___G_c_23_env_2d_macro,119)
___DEF_MOD_GLO(26,___G_c_23_env_2d_macros_2d_set,128)
___DEF_MOD_GLO(13,___G_c_23_env_2d_declare,133)
___DEF_MOD_GLO(12,___G_c_23_env_2d_decl_2d_set,138)
___DEF_MOD_GLO(27,___G_c_23_env_2d_namespace,143)
___DEF_MOD_GLO(31,___G_c_23_env_2d_namespace_2d_set,148)
___DEF_MOD_GLO(34,___G_c_23_env_2d_vars_2d_ref,153)
___DEF_MOD_GLO(25,___G_c_23_env_2d_macros_2d_ref,155)
___DEF_MOD_GLO(11,___G_c_23_env_2d_decl_2d_ref,157)
___DEF_MOD_GLO(30,___G_c_23_env_2d_namespace_2d_ref,159)
___DEF_MOD_GLO(33,___G_c_23_env_2d_parent_2d_ref,161)
___DEF_MOD_GLO(15,___G_c_23_env_2d_externals_2d_ref,163)
___DEF_MOD_GLO(17,___G_c_23_env_2d_frame_2d_lookup_2d_var,165)
___DEF_MOD_GLO(28,___G_c_23_env_2d_namespace_2d_lookup,171)
___DEF_MOD_GLO(29,___G_c_23_env_2d_namespace_2d_lookup_2d_both,182)
___DEF_MOD_GLO(41,___G_c_23_macro_2d_list_2d_cached,200)
___DEF_MOD_GLO(42,___G_c_23_macro_2d_list_2d_empty,203)
___DEF_MOD_GLO(48,___G_c_23_macro_2d_list_2d_ref,206)
___DEF_MOD_GLO(44,___G_c_23_macro_2d_list_2d_flatten,215)
___DEF_MOD_GLO(43,___G_c_23_macro_2d_list_2d_extend,235)
___DEF_MOD_GLO(47,___G_c_23_macro_2d_list_2d_prefix_2d_length,244)
___DEF_MOD_GLO(49,___G_c_23_macro_2d_list_2d_suffix,252)
___DEF_MOD_GLO(46,___G_c_23_macro_2d_list_2d_overlay_2d_prefix,255)
___DEF_MOD_GLO(50,___G_c_23_macro_2d_list_2d_table,261)
___DEF_MOD_GLO(20,___G_c_23_env_2d_lookup,279)
___DEF_MOD_GLO(60,___G_c_23_namespace_2d_valid_3f_,300)
___DEF_MOD_GLO(39,___G_c_23_full_2d_name_3f_,302)
___DEF_MOD_GLO(52,___G_c_23_make_2d_full_2d_name,309)
___DEF_MOD_GLO(23,___G_c_23_env_2d_lookup_2d_var,317)
___DEF_MOD_GLO(14,___G_c_23_env_2d_define_2d_var,329)
___DEF_MOD_GLO(21,___G_c_23_env_2d_lookup_2d_global_2d_var,342)
___DEF_MOD_GLO(19,___G_c_23_env_2d_global_2d_variables,349)
___DEF_MOD_GLO(18,___G_c_23_env_2d_global_2d_env,354)
___DEF_MOD_GLO(22,___G_c_23_env_2d_lookup_2d_macro,358)
___DEF_MOD_GLO(6,___G_c_23_define_2d_flag_2d_decl,366)
___DEF_MOD_GLO(9,___G_c_23_define_2d_parameterized_2d_decl,370)
___DEF_MOD_GLO(5,___G_c_23_define_2d_boolean_2d_decl,374)
___DEF_MOD_GLO(8,___G_c_23_define_2d_namable_2d_decl,378)
___DEF_MOD_GLO(7,___G_c_23_define_2d_namable_2d_boolean_2d_decl,382)
___DEF_MOD_GLO(37,___G_c_23_flag_2d_decl,386)
___DEF_MOD_GLO(62,___G_c_23_parameterized_2d_decl,390)
___DEF_MOD_GLO(1,___G_c_23_boolean_2d_decl,394)
___DEF_MOD_GLO(58,___G_c_23_namable_2d_decl,398)
___DEF_MOD_GLO(56,___G_c_23_namable_2d_boolean_2d_decl,402)
___DEF_MOD_GLO(4,___G_c_23_declaration_2d_value,406)
___DEF_MOD_GLO(35,___G_c_23_env_2e_begin_21_,415)
___DEF_MOD_GLO(36,___G_c_23_env_2e_end_21_,424)
___END_MOD_GLO

___BEGIN_MOD_SYM_KEY
___DEF_MOD_SYM(0,___S___env,"_env")
___DEF_MOD_SYM(1,___S___env_23_,"_env#")
___DEF_MOD_SYM(2,___S_c_23_boolean_2d_decl,"c#boolean-decl")
___DEF_MOD_SYM(3,___S_c_23_declaration_2d_value,"c#declaration-value")
___DEF_MOD_SYM(4,___S_c_23_define_2d_boolean_2d_decl,"c#define-boolean-decl")
___DEF_MOD_SYM(5,___S_c_23_define_2d_flag_2d_decl,"c#define-flag-decl")
___DEF_MOD_SYM(6,___S_c_23_define_2d_namable_2d_boolean_2d_decl,"c#define-namable-boolean-decl")

___DEF_MOD_SYM(7,___S_c_23_define_2d_namable_2d_decl,"c#define-namable-decl")
___DEF_MOD_SYM(8,___S_c_23_define_2d_parameterized_2d_decl,"c#define-parameterized-decl")
___DEF_MOD_SYM(9,___S_c_23_env_2d_decl_2d_ref,"c#env-decl-ref")
___DEF_MOD_SYM(10,___S_c_23_env_2d_decl_2d_set,"c#env-decl-set")
___DEF_MOD_SYM(11,___S_c_23_env_2d_declare,"c#env-declare")
___DEF_MOD_SYM(12,___S_c_23_env_2d_define_2d_var,"c#env-define-var")
___DEF_MOD_SYM(13,___S_c_23_env_2d_externals_2d_ref,"c#env-externals-ref")
___DEF_MOD_SYM(14,___S_c_23_env_2d_frame,"c#env-frame")
___DEF_MOD_SYM(15,___S_c_23_env_2d_frame_2d_lookup_2d_var,"c#env-frame-lookup-var")
___DEF_MOD_SYM(16,___S_c_23_env_2d_global_2d_env,"c#env-global-env")
___DEF_MOD_SYM(17,___S_c_23_env_2d_global_2d_variables,"c#env-global-variables")
___DEF_MOD_SYM(18,___S_c_23_env_2d_lookup,"c#env-lookup")
___DEF_MOD_SYM(19,___S_c_23_env_2d_lookup_2d_global_2d_var,"c#env-lookup-global-var")
___DEF_MOD_SYM(20,___S_c_23_env_2d_lookup_2d_macro,"c#env-lookup-macro")
___DEF_MOD_SYM(21,___S_c_23_env_2d_lookup_2d_var,"c#env-lookup-var")
___DEF_MOD_SYM(22,___S_c_23_env_2d_macro,"c#env-macro")
___DEF_MOD_SYM(23,___S_c_23_env_2d_macros_2d_ref,"c#env-macros-ref")
___DEF_MOD_SYM(24,___S_c_23_env_2d_macros_2d_set,"c#env-macros-set")
___DEF_MOD_SYM(25,___S_c_23_env_2d_namespace,"c#env-namespace")
___DEF_MOD_SYM(26,___S_c_23_env_2d_namespace_2d_lookup,"c#env-namespace-lookup")
___DEF_MOD_SYM(27,___S_c_23_env_2d_namespace_2d_lookup_2d_both,"c#env-namespace-lookup-both")
___DEF_MOD_SYM(28,___S_c_23_env_2d_namespace_2d_ref,"c#env-namespace-ref")
___DEF_MOD_SYM(29,___S_c_23_env_2d_namespace_2d_set,"c#env-namespace-set")
___DEF_MOD_SYM(30,___S_c_23_env_2d_new_2d_var_21_,"c#env-new-var!")
___DEF_MOD_SYM(31,___S_c_23_env_2d_parent_2d_ref,"c#env-parent-ref")
___DEF_MOD_SYM(32,___S_c_23_env_2d_vars_2d_ref,"c#env-vars-ref")
___DEF_MOD_SYM(33,___S_c_23_env_2e_begin_21_,"c#env.begin!")
___DEF_MOD_SYM(34,___S_c_23_env_2e_end_21_,"c#env.end!")
___DEF_MOD_SYM(35,___S_c_23_flag_2d_decl,"c#flag-decl")
___DEF_MOD_SYM(36,___S_c_23_full_2d_name_3f_,"c#full-name?")
___DEF_MOD_SYM(37,___S_c_23_macro_2d_list_2d_cached,"c#macro-list-cached")
___DEF_MOD_SYM(38,___S_c_23_macro_2d_list_2d_empty,"c#macro-list-empty")
___DEF_MOD_SYM(39,___S_c_23_macro_2d_list_2d_extend,"c#macro-list-extend")
___DEF_MOD_SYM(40,___S_c_23_macro_2d_list_2d_flatten,"c#macro-list-flatten")
___DEF_MOD_SYM(41,___S_c_23_macro_2d_list_2d_overlay_2d_prefix,"c#macro-list-overlay-prefix")
___DEF_MOD_SYM(42,___S_c_23_macro_2d_list_2d_prefix_2d_length,"c#macro-list-prefix-length")
___DEF_MOD_SYM(43,___S_c_23_macro_2d_list_2d_ref,"c#macro-list-ref")
___DEF_MOD_SYM(44,___S_c_23_macro_2d_list_2d_suffix,"c#macro-list-suffix")
___DEF_MOD_SYM(45,___S_c_23_macro_2d_list_2d_table,"c#macro-list-table")
___DEF_MOD_SYM(46,___S_c_23_make_2d_full_2d_name,"c#make-full-name")
___DEF_MOD_SYM(47,___S_c_23_make_2d_temp_2d_var,"c#make-temp-var")
___DEF_MOD_SYM(48,___S_c_23_make_2d_var,"c#make-var")
___DEF_MOD_SYM(49,___S_c_23_namable_2d_boolean_2d_decl,"c#namable-boolean-decl")
___DEF_MOD_SYM(50,___S_c_23_namable_2d_decl,"c#namable-decl")
___DEF_MOD_SYM(51,___S_c_23_namespace_2d_valid_3f_,"c#namespace-valid?")
___DEF_MOD_SYM(52,___S_c_23_parameterized_2d_decl,"c#parameterized-decl")
___DEF_MOD_SYM(53,___S_c_23_resize_2d_var_2d_list,"c#resize-var-list")
___DEF_MOD_SYM(54,___S_c_23_var_2d_bound,"c#var-bound")
___DEF_MOD_SYM(55,___S_c_23_var_2d_bound_2d_set_21_,"c#var-bound-set!")
___DEF_MOD_SYM(56,___S_c_23_var_2d_boxed_3f_,"c#var-boxed?")
___DEF_MOD_SYM(57,___S_c_23_var_2d_boxed_3f__2d_set_21_,"c#var-boxed?-set!")
___DEF_MOD_SYM(58,___S_c_23_var_2d_clone,"c#var-clone")
___DEF_MOD_SYM(59,___S_c_23_var_2d_clone_2d_set_21_,"c#var-clone-set!")
___DEF_MOD_SYM(60,___S_c_23_var_2d_constant,"c#var-constant")
___DEF_MOD_SYM(61,___S_c_23_var_2d_constant_2d_set_21_,"c#var-constant-set!")
___DEF_MOD_SYM(62,___S_c_23_var_2d_info,"c#var-info")
___DEF_MOD_SYM(63,___S_c_23_var_2d_info_2d_set_21_,"c#var-info-set!")
___DEF_MOD_SYM(64,___S_c_23_var_2d_lexical_2d_level,"c#var-lexical-level")
___DEF_MOD_SYM(65,___S_c_23_var_2d_name,"c#var-name")
___DEF_MOD_SYM(66,___S_c_23_var_2d_name_2d_set_21_,"c#var-name-set!")
___DEF_MOD_SYM(67,___S_c_23_var_2d_refs,"c#var-refs")
___DEF_MOD_SYM(68,___S_c_23_var_2d_refs_2d_set_21_,"c#var-refs-set!")
___DEF_MOD_SYM(69,___S_c_23_var_2d_sets,"c#var-sets")
___DEF_MOD_SYM(70,___S_c_23_var_2d_sets_2d_set_21_,"c#var-sets-set!")
___DEF_MOD_SYM(71,___S_c_23_var_2d_source,"c#var-source")
___DEF_MOD_SYM(72,___S_c_23_var_2d_source_2d_set_21_,"c#var-source-set!")
___DEF_MOD_SYM(73,___S_c_23_var_2d_stamp,"c#var-stamp")
___DEF_MOD_SYM(74,___S_c_23_var_2d_stamp_2d_set_21_,"c#var-stamp-set!")
___DEF_MOD_SYM(75,___S_c_23_var_2d_temp_3f_,"c#var-temp?")
___DEF_MOD_SYM(76,___S_c_23_var_2d_temp_3f__2d_set_21_,"c#var-temp?-set!")
___DEF_MOD_SYM(77,___S_c_23_var_3f_,"c#var?")
___DEF_MOD_SYM(78,___S_closure_2d_env,"closure-env")
___DEF_MOD_SYM(79,___S_macro_2d_index_2d_miss,"macro-index-miss")
___DEF_MOD_SYM(80,___S_macro_2d_overlay,"macro-overlay")
___DEF_MOD_SYM(81,___S_ret,"ret")
___DEF_MOD_SYM(82,___S_var_2d_tag,"var-tag")
___DEF_MOD_KEY(0,___K_test,"test")
___DEF_MOD_KEY(1,___K_weak_2d_keys,"weak-keys")
___END_MOD_SYM_KEY

#endif
