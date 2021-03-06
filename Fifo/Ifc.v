Require Import Kami.AllNotations.

Section Ifc.
  Class Params := { name: string;
                    k: Kind;
                    size: nat;
                    lgSize := Nat.log2_up size ;
                    }.

  Context {params: Params}.

  Record Ifc: Type :=
    {
      regs: list RegInitT;
      regFiles: list RegFileBase;
      isEmpty: forall {ty}, ActionT ty Bool;
      isFull: forall {ty}, ActionT ty Bool;
      numFree: forall {ty}, ActionT ty (Bit lgSize);
      first: forall {ty}, ActionT ty (Maybe k);
      deq: forall {ty}, ActionT ty (Maybe k);
      enq: forall {ty}, ty k -> ActionT ty Bool;
      flush: forall {ty}, ActionT ty Void
    }.
End Ifc.
