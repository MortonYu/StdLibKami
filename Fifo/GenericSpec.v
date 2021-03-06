Require Import Kami.AllNotations.
Require Import StdLibKami.RegArray.Ifc.
Require Import StdLibKami.Fifo.Ifc.

Section GenSpec.
  Context {ifcParams : Ifc.Params}.

  Class Params := { sizePow2 : Nat.pow 2 lgSize = size;
                    regList : list RegInitT;
                  }.

  Context {params : Params}.

  Local Definition listName := (name ++ ".list")%string.
  Local Definition nonDetName := (name ++ ".nonDet")%string.
  
  Local Notation Natgeb n m := (negb (Nat.ltb n m)).
  
  Local Open Scope kami_expr.
  Local Open Scope kami_action.
  
  Local Definition getHead ty (ls : list (ty k)): k @# ty :=
    match ls with
    | [] => $$(getDefaultConst k)
    | x :: _ => #x
    end.

  Local Definition nonDet ty: ActionT ty Void :=
    Nondet eps: (Bit lgSize);
    Write nonDetName: (Bit lgSize) <- #eps;
    Retv.
  
  Local Definition snocInBound ty (a : ty k) (ls : list (ty k)) : list (ty k) :=
    if (Nat.ltb (length ls) size) then snoc a ls else ls.
  
  Local Definition nlist ty := NativeKind (nil : list (ty k)).

  Local Definition numFree ty: ActionT ty (Bit lgSize) :=
    ReadN data: nlist ty <- listName;
    Read eps: (Bit lgSize) <- nonDetName;    
    Ret (IF (#eps < $(size - (length data))) then #eps else $(size - (length data))).
  
  Local Definition isEmpty ty: ActionT ty Bool :=
    LETA freeNum: (Bit lgSize) <- numFree ty;
    Ret (#freeNum == $0).

  Local Definition isFull ty: ActionT ty Bool :=
    LETA freeNum: (Bit lgSize) <- numFree ty;
    Ret (#freeNum == $size).
  
  Local Definition first ty: ActionT ty (Maybe k) :=
    ReadN data: nlist ty <- listName;
    LETA empty: Bool <- isEmpty ty;
    Ret (STRUCT { "valid" ::= #empty;
                  "data" ::= getHead _ data } : Maybe k @# ty).

  Local Definition deq ty: ActionT ty (Maybe k) :=
    ReadN data: nlist ty <- listName;
    LETA empty: Bool <- isEmpty ty;
    Ret (STRUCT { "valid" ::= #empty;
                  "data" ::= getHead _ data } : Maybe k @# ty).
  
  Local Definition enq ty (new: ty k): ActionT ty Bool :=
    ReadN data: nlist ty <- listName;
    LETA full: Bool <- isFull ty;
    WriteN listName: nlist ty <- Var _ (nlist ty) (snocInBound ty new data);
    Ret #full.

  Local Definition flush ty: ActionT ty Void :=
    WriteN listName: nlist ty <- Var _ (nlist ty) nil;
    Retv.

  Local Definition regs : list RegInitT :=
    makeModule_regs (RegisterNDef listName: list (type k) <- (nil: list (type k)))%kami.

  Definition spec: Ifc :=
    {|
      Ifc.regs := regs;
      Ifc.regFiles := nil;
      Ifc.isEmpty := isEmpty;
      Ifc.isFull := isFull;
      Ifc.numFree := numFree;
      Ifc.first := first;
      Ifc.deq := deq;
      Ifc.enq := enq;
      Ifc.flush := flush
    |}.
  
End GenSpec.
