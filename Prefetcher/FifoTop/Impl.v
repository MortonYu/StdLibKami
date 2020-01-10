(* TODO: LLEE rename to Impl.v *)
Require Import Kami.AllNotations.
Require Import StdLibKami.Fifo.Ifc.
Require Import StdLibKami.Fifo.Async.
Require Import StdLibKami.Prefetcher.FifoTop.Ifc.
Section AsyncFifoTop.
  Context `{FifoTopParams}.
  Class AsyncFifoTopParams :=
    {
      backingFifo: @Fifo PrefetcherFifoEntry;
      topReg: string;
      isCompleting: string;
    }.
  Section withParams.
    Context `{AsyncFifoTopParams}.
    Local Open Scope kami_expr.
    Local Open Scope kami_action.
    
    Definition toFullVAddr {ty} (short: ty ShortVAddr): VAddr @# ty := ZeroExtendTruncLsb _ ({< #short, $$(natToWord 2 0) >}).
  
    Definition toShortVAddr {ty} (long: ty VAddr): ShortVAddr @# ty := ZeroExtendTruncMsb _ #long.
    
    Section withTy.
    Context (ty: Kind -> Type).
    
    Definition GetIsCompleting: ActionT ty (Maybe VAddr) :=
      Read completing: Maybe VAddr <- isCompleting;
      Ret #completing.

    Definition SetIsCompleting (p: ty (Maybe VAddr)): ActionT ty Void :=
      Write isCompleting: Maybe VAddr <- #p;
      Retv.

    Local Definition TopIsEmpty: ActionT ty Bool :=
      Read top: TopEntry <- topReg;
      (* COQBUG: typeclass instance resolution fails *)
      LET upper: Maybe (@CompInst H) <- #top @% "upper";
      Ret !(#upper @% "valid"). (* we maintain the invariant that the upper portion of the top register is valid for any non-empty Fifo *)
  
    Definition isEmpty: ActionT ty Bool :=
      LETA topEmpty: Bool <- TopIsEmpty;
      LETA fifoEmpty: Bool <- (@Fifo.Ifc.isEmpty _ backingFifo ty);
      Ret (#topEmpty && #fifoEmpty).

    Definition isFull: ActionT ty Bool :=
      LETA fifoFull: Bool <- (@Fifo.Ifc.isFull _ backingFifo ty);
      Ret #fifoFull.
  
    (*
      NOTE: this is RISC-V specific and shouldn't be in
      StdLibKami. If the following definitions depend on this,
      then the Prefetcher needs to be moved to ProcKami.
    *)
    Local Definition isCompressed (inst : CompInst @# ty)
      := (ZeroExtendTruncLsb 2 inst != $$(('b"11") : word 2)).

    Definition deq : ActionT ty DeqRes
      := Ret $$(getDefaultConst (DeqRes)).
(*
-    Definition deq: ActionT ty DeqRes := 
-      Read top: TopEntry <- topReg;
-      Read completing: Maybe PAddr <- isCompleting;
-      LETA FifoEmpty: Bool <- (Fifo.Ifc.isEmpty backingFifo);
-      LETA ftop: Maybe AddrInst <- (Ifc.first backingFifo);
-      
-      LET topAddr: Maybe ShortPAddr <- #top @% "addr";
-      LET lower: Maybe CompInst <- #top @% "lower";
-      LET lowerValid: Bool <- #lower @% "valid";
-      LET lowerInst: CompInst <- #lower @% "data";
-      LET lowerCompressed: Bool <- isCompressed #lowerInst;
-      LET upper: Maybe CompInst <- #top @% "upper";
-      LET upperValid: Bool <- #upper @% "valid";
-      LET upperInst: CompInst <- #upper @% "data";
-      LET upperCompressed: Bool <- isCompressed #upperInst;
-      LET ftopAddrInst: AddrInst <- #ftop @% "data";
-      LET ftopAddr: Maybe ShortPAddr <- #ftopAddrInst @% "addr";
-      LET ftopInst: Inst <- #ftopAddrInst @% "inst";
-      LET ftopUpperInst: CompInst <- ZeroExtendTruncMsb _ #ftopInst;
-      LET ftopLowerInst: CompInst <- ZeroExtendTruncLsb _ #ftopInst;
-      LET lowerFull: Inst <- (ZeroExtend _ #lowerInst: Inst @# ty);
-      LET upperFull: Inst <- (ZeroExtend _ #upperInst: Inst @# ty);
-      LET full: Inst <- {< #upperInst, #lowerInst >};
-      LET completedInst: Inst <- {< #ftopLowerInst, #upperInst >};
-      LET topAddrDat: ShortPAddr <- (#topAddr @% "data");
-      LET retAddr: Maybe PAddr <- STRUCT { "valid" ::= #upperValid && (#topAddr @% "valid");
-                                           "data" ::= (IF #lowerValid
-                                                       then toFullPAddr topAddrDat
-                                                       else (IF #upperCompressed || (!#FifoEmpty && ((#ftopAddr @% "data") == (#topAddrDat + $1)))
-                                                             then toFullPAddr topAddrDat + $2
-                                                             else toFullPAddr topAddrDat + $4)) };
-      LET retInst: Maybe Inst <- STRUCT { "valid" ::= (IF !#upperValid
-                                                       then $$false
-                                                       else (IF #lowerValid
-                                                             then $$true
-                                                             else (IF #upperCompressed
-                                                                   then $$true
-                                                                   else (!#FifoEmpty && ((#ftopAddr @% "data") == (#topAddrDat + $1))))));
-                                          "data" ::= (IF #lowerValid
-                                                      then (IF #lowerCompressed
-                                                            then #lowerFull
-                                                            else #full)
-                                                      else (IF #upperCompressed
-                                                            then #upperFull
-                                                            else #completedInst)) };
-      LET retError: DeqError <- IF (#retAddr @% "valid") then (IF #retInst @% "valid" then $NoError else $IncompleteError) else (IF #retInst @% "valid" then $DevError else $EmptyError);
-      LET newIsCompleting: Maybe PAddr <- (IF (#retAddr @% "valid") && !(#retInst @% "valid")
-                                           then Valid (toFullPAddr topAddrDat + $4)
-                                           else #completing);
-      LET ret: DeqRes <- STRUCT { "error" ::= #retError;
-                                  "addr" ::= #retAddr @% "data"; 
-                                  "inst" ::= #retInst @% "data"};
-      LET doDequeue: Bool <- (#retAddr @% "valid") && (#retInst @% "valid");
-      (* Flush when we will return valid, invalid *)
-      LET doFlush: Bool <- (#retAddr @% "valid") && !(#retInst @% "valid");
-      LET newTopAddr: Maybe ShortPAddr <- (STRUCT { "valid" ::= IF #doDequeue then (#ftopAddr @% "valid") else #topAddr @% "valid"; (* TODO: is this right? *)
-                                                    "data" ::= IF #doDequeue then (#ftopAddr @% "data") else #topAddrDat});
-      LET newTopUpperInst: Maybe CompInst <- STRUCT { "valid" ::= IF #doDequeue then !#FifoEmpty else #upperValid;
-                                                      "data" ::= IF #doDequeue then #ftopUpperInst else #upperInst };
-      LET newTopLowerInst: Maybe CompInst <- 
-                                 (IF !#upperValid 
-                                  then #lower
-                                  else
-                                    (IF #lowerValid
-                                     then (IF #lowerCompressed
-                                           then Invalid
-                                           else (IF !#FifoEmpty
-                                                 then Valid #ftopLowerInst
-                                                 else Invalid))
-                                     else (IF #upperCompressed
-                                           then (IF !#FifoEmpty
-                                                 then Valid #ftopLowerInst
-                                                 else Invalid)
-                                           else Invalid)));
-      LET newTop: TopEntry <- STRUCT { "addr" ::= #newTopAddr;
-                                       "upper" ::= #newTopUpperInst;
-                                       "lower" ::= #newTopLowerInst };
 
-      If #doDequeue then ( LETA _ <- (Fifo.Ifc.deq backingFifo); Retv );
-      If #doFlush then ( LETA _ <- (Fifo.Ifc.flush backingFifo); Retv );
-      Write isCompleting: Maybe PAddr <- #newIsCompleting;
-      Write topReg: TopEntry <- #newTop;
-      Ret #ret.
*)

    Definition enq (new: ty (Maybe PrefetcherFifoEntry)) : ActionT ty Bool
      := Ret $$true.
(*
-    Definition enq (new: ty AddrInst): ActionT ty Bool := 
-      Read top: TopEntry <- topReg;
-      Read completing: Maybe PAddr <- isCompleting;
-      LETA isFull: Bool <- (Fifo.Ifc.isFull backingFifo);
-      LETA isEmpty: Bool <- isEmpty;
-      
-      LET inst: Inst <- #new @% "inst";
-      LET addr <- #new @% "addr";
-      LET addrDat <- #addr @% "data";
-      LET addrValid <- #addr @% "valid";
-      LET completingAddr: PAddr <- #completing @% "data";
-      LET newCompleting: Maybe PAddr <- (IF (toFullPAddr addrDat) == #completingAddr && #addrValid
-                                         then Invalid
-                                         else #completing);
-      (* if the Fifo + top are both entirely empty, we should put the new entry into the top register*)
-      (* otherwise, just fall through to the Fifo enqueue *)
-      If !#isEmpty
-      then (LETA _ <- (Fifo.Ifc.enq backingFifo) new; Retv)
-      else (Write topReg: TopEntry <- (STRUCT { "addr" ::= #addr;
-                                                "upper" ::= Valid (ZeroExtendTruncMsb CompInstSz #inst);
-                                                "lower" ::= Valid (ZeroExtendTruncLsb CompInstSz #inst) });
-            Retv);
-      Write isCompleting: Maybe PAddr <- #newCompleting;
-      Ret !#isFull.
*)

    Definition flush: ActionT ty Void :=
      LETA _ <- (@Fifo.Ifc.flush _ backingFifo ty);
      Write topReg
        :  TopEntry
        <- STRUCT {
             "vaddr"  ::= $$(getDefaultConst (Maybe ShortVAddr));
             "upper" ::= Invalid;
             "lower" ::= Invalid
           };
      Retv.
    
    End withTy.

    Open Scope kami_scope.
    Open Scope kami_expr_scope.

    Definition regs: list RegInitT := makeModule_regs ( Register topReg: TopEntry <- Default ++
                                                        Register isCompleting: Maybe VAddr <- Default )
                                      ++ (@Fifo.Ifc.regs _ backingFifo).
    
    Instance asyncFifoTop: FifoTop.Ifc.FifoTop := 
      {|
        FifoTop.Ifc.regs := regs;
        FifoTop.Ifc.getIsCompleting := GetIsCompleting;
        FifoTop.Ifc.isEmpty := isEmpty;
        FifoTop.Ifc.isFull := isFull;
        FifoTop.Ifc.deq := deq;
        FifoTop.Ifc.enq := enq;
        FifoTop.Ifc.flush := flush;
      |}.
  End withParams.
End AsyncFifoTop.
