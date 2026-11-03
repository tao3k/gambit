/* VM storage is independent of the shared global identity registry.
 * One page has one machine word of primitive-presence bits. Directory growth
 * is geometric, not a registration limit. Published cells never move.
 * Insertions are serialized by global_gate; readers acquire published pointers.
 * Old directories remain owned by this VM until its existing cleanup permit.
 */
#ifndef ___SINGLE_VM
/* All allocations precede publication. No Scheme allocation, GC, callback or
 * safepoint occurs here. Failure leaves the old directory and cells intact. */
___HIDDEN ___BOOL global_prepare_locked(___virtual_machine_state vm, int id)
{
  ___global_slot_store *store=vm->glos;
  ___global_slot_directory *directory, *replacement=0;
  ___global_slot_page *page, *p;
  ___SIZE_T capacity, position, i;
  if (___global_page(vm,id)!=0) return 1;
  if (store==0 || id<0 || store->count>=INT_MAX) return 0;
  directory=store->directory;
  capacity=directory==0 ? ___WORD_WIDTH : directory->capacity;
  if (directory==0 || store->count>=capacity/2) {
    ___SIZE_T bytes;
    if (directory!=0) {
      if (capacity>~___CAST(___SIZE_T,0)/2) return 0;
      capacity*=2;
    }
    if (capacity-1>(~___CAST(___SIZE_T,0)-sizeof(*directory))/sizeof(directory->entries[0])) return 0;
    bytes=sizeof(*directory)+(capacity-1)*sizeof(directory->entries[0]);
    replacement=___CAST(___global_slot_directory*,___ALLOC_MEM(bytes));
    if (replacement==0) return 0;
    replacement->capacity=capacity; replacement->retired=directory;
    for (i=0;i<capacity;i++) replacement->entries[i]=0;
    for (p=store->pages;p!=0;p=p->next) {
      position=p->key&(capacity-1);
      while (replacement->entries[position]!=0) position=(position+1)&(capacity-1);
      replacement->entries[position]=p;
    }
  }
  page=___CAST(___global_slot_page*,___ALLOC_MEM(sizeof(*page)));
  if (page==0) { if (replacement!=0) ___FREE_MEM(replacement); return 0; }
  page->key=___CAST(___SIZE_T,id)/___WORD_WIDTH;
  page->primitive_set=0;
  for (i=0;i<___WORD_WIDTH;i++) {
    page->ordinary[i]=___UNB1; page->primitive[i]=___FAL;
  }
  page->next=store->pages;
  if (replacement!=0) directory=replacement;
  position=page->key&(directory->capacity-1);
  while (directory->entries[position]!=0) position=(position+1)&(directory->capacity-1);
  store->pages=page; ++store->count;
  ___WORD_STORE_RELEASE(&directory->entries[position],page);
  if (replacement!=0) ___WORD_STORE_RELEASE(&store->directory,replacement);
  return 1;
}

___HIDDEN void global_storage_cleanup(___virtual_machine_state vm)
{
  ___global_slot_store *store=vm->glos;
  if (store!=0) {
    ___global_slot_page *page=store->pages;
    ___global_slot_directory *directory=store->directory;
    while (page!=0) { ___global_slot_page *next=page->next; ___FREE_MEM(page); page=next; }
    while (directory!=0) { ___global_slot_directory *next=directory->retired; ___FREE_MEM(directory); directory=next; }
    ___FREE_MEM(store); vm->glos=0;
  }
}
#endif

/* Read-only lookup never allocates. Generated writes use store_global;
 * the VM-local unbound sentinel is not a writable global binding. */
___EXP_FUNC(___SCMOBJ*,___global_cell)
   ___P((___virtual_machine_state vm, int id), (vm,id)
___virtual_machine_state vm; int id;)
{
#ifdef ___SINGLE_VM
  (void)vm; (void)id; return 0; /* SINGLE_VM macros use the cell in glo. */
#else
  return ___global_cell_address(vm,id);
#endif
}
