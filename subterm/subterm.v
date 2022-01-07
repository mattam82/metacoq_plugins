From MetaCoq.PCUIC Require Import PCUICAst PCUICAstUtils PCUICLiftSubst.
From MetaCoq.PCUIC Require TemplateToPCUIC PCUICToTemplate.

From MetaCoq.Template Require Import config monad_utils utils TemplateMonad Universes.
From MetaCoq.Template Require Ast.
Import MCMonadNotation.

Require Import List String Relation_Operators.
Import ListNotations.

From MetaCoq.Translations Require Import param_all.

From Local Require Import non_uniform.

Import IfNotations.

Variant subInstance :=
  | IndInst (params:list term)
  | NestInst (arguments:list term) (ind:inductive) (inst:Instance.t).

Fixpoint filter_map {X Y} (f:X->option Y) xs :=
  match xs with
  | [] => []
  | y::ys => 
    if f y is Some a then a::filter_map f ys else filter_map f ys
  end.

Definition filter_mapi {X Y} (f:nat->X->option Y) xs :=
  filter_map (fun x => x) (mapi f xs).

Definition index {X} :=
  mapi (A:=X) (fun i x => (i,x)).


Inductive List (X:Set) : Set := Nil | Cons (x:X) (xs:List X).
MetaCoq Run Derive Translations for List.
  MetaCoq Quote Definition TrueQ := True.
  MetaCoq Quote Definition ListQ := List.
  MetaCoq Quote Definition ListEQ := Listᴱ.
  MetaCoq Quote Definition EqQ := @eq.

Definition subterms_for_constructor
           (refi : inductive)
           (ref   : term) (* we need the term for exactly this inductive just for the substition *)
           (ntypes : nat) (* number of types in the mutual inductive *)
           (npars : nat) (* number of parameters in the type *)
           (nind : nat) (* number of proper indices in the type *)
           (ct    : term) (* type of the constructor *)
           (ncons : nat) (* index of the constructor in the inductive *)
           (nargs : nat) (* number of arguments in this constructor *)
                  : list (nat * (term * nat))
  := let indrel := (ntypes - inductive_ind refi - 1) in
    let '(ctx, ap) := decompose_prod_assum [] ct in
    (*    ^ now ctx is a reversed list of assumptions and definitions *)
    let len := List.length ctx in
    let params := List.skipn (len - npars) (ctx) in
    let inds := List.skipn npars (snd (decompose_app ap)) in
    (* d is a list of occurences of subterms in arguments to the constructor *)
    let d :=List.concat (
           (* so this i represents distance from return object to `t` *)
              mapi (fun i t =>
                      let '(ctx, ar) := decompose_prod_assum [] (decl_type t)
                      in let p := (indrel + (len - i - 1) + List.length (ctx)) (* distance to ind *)
                      in let (f, s) := decompose_app ar
                      in match f with
                         | tRel j => if Nat.eqb p j (* recursive call to ind *)
                                    then [(i, ctx, IndInst s)] (* index of arg, binders, applications *)
                                    else []
                         | tInd ind inst => [(i,ctx,NestInst s ind inst)]
                         | _ => []
                         end) ctx) in
    let '(ctx_sbst, _) := decompose_prod_assum [] (subst1 ref indrel ct) in
    (* ^ replace tRel with tInd for the type in question *)
    let construct_cons :=
        fun (* index of a subterm in this constructor *)
          (i: nat)
          (* these are arguments for the function
             that is a parameter of the constructor
             and if applied fully returns something of the needed type *)
          (ctx': context)
          (* these are arguments of the type of the subterm *)
          (subInst:subInstance) =>
          match subInst with
          | IndInst args' =>
            let len' := List.length ctx' in (* number of binders *)
            let ctxl' := (map_context (lift0 (2 + i)) ctx') in (* lift over other args (i) and own arg (1) *)
            Some (it_mkProd_or_LetIn
              (ctxl' ++ ctx_sbst)
              (mkApps (tRel (len + len'))
                    ((map (lift0 (len' + len - npars))
                          (to_extended_list params)) ++ (* parameters *)
                      (map (lift (1 + i + len') len') (List.skipn npars args')) ++ (* indices of subterm instance *)
                      (map (lift0 len') inds) ++ (* indices of constructed inductive inst *)
                      [mkApps (tRel (i + len')) (* subterm instance *)
                            (to_extended_list ctxl');
                      mkApps (tConstruct refi ncons []) (* inductive instance *)
                          (map (lift0 len') (to_extended_list ctx_sbst))])))
          | NestInst args ind inst => 
            let len' := List.length ctx' in (* number of binders *)
            let ctxl' := (map_context (lift0 (2 + i)) ctx') in (* lift over other args (i) and own arg (1) *)
            match args with (* special case for list *)
            | [] => None
            | _::_::_ => None
            | [arg] =>
            Some (it_mkProd_or_LetIn
              (
                [
                  vass ({| binder_name := nNamed "Hxs"; binder_relevance := Relevant |}) 
                  (
                    (* TemplateToPCUIC.trans TrueQ *)
                    (* mkApps (TemplateToPCUIC.trans ListQ)
                    [mkApps ref [tRel 3]] *)
                    (* (map (lift (i+len'+1) len') (List.firstn 1 args)) *)
                    (* [ TemplateToPCUIC.trans TrueQ ] *)

                    (* TODO *)
                    (* let containee := mkApps ref [tRel 3] in *)
                    let containee := 
                    lift (2 + i + len') len'
                      (subst1 ref (
                        indrel + (len - i - 1) + List.length (ctx')
                      ) arg) in

                    (* TODO *)
                    mkApps (TemplateToPCUIC.trans ListEQ)
                      [
                        containee;
                        (tLambda 
                          {| binder_name := nAnon; binder_relevance := Relevant |}
                          containee
                          (* (TemplateToPCUIC.trans TrueQ) *)
                          (
                          mkApps (TemplateToPCUIC.trans EqQ)
                          [
                            (lift0 1 containee);
                            tRel 0;
                            tRel 1
                          ]
                          )
                        );
                        tRel (i + len'+1) (* container *)
                      ]

                    (* (map (lift (1 + i + len') len')
                          (args)) *)
                  );
                  (* (TemplateToPCUIC.trans TrueQ); *)

                  (* witness instance:
                  forall non-uniform indices, tInd params non-uni indices
                  TODO: forall quantification
                   *)
                  vass ({| binder_name := nAnon; binder_relevance := Relevant |})
                  (mkApps ref (
                    (map (lift0 (len' + len - npars))
                          (to_extended_list params)) ++
                    (map (lift0 len') inds) (* use local indice quantification instead *)
                  ))
                ]
                 ++ ctxl' ++ ctx_sbst)
                 (* +2 => subterm witness and subterm property (Exists parametricity) *)
              (mkApps (tRel (len + len'+2))
                    ((map (lift0 (len' + len - npars+2))
                          (to_extended_list params)) ++ (* parameters *)
                      (map (lift0 (len'+2)) inds) ++ (* indices of constructed inductive inst *)
                      (map (lift0 (len'+2)) inds) ++ (* indices of constructed inductive inst *)
                      [
                        tRel 1;
                      (* mkApps (tConstruct refi ncons []) (* inductive instance *)
                          (map (lift0 (len'+1)) (to_extended_list ctx_sbst)); *)
                      mkApps (tConstruct refi ncons []) (* inductive instance *)
                          (map (lift0 (len'+2)) (to_extended_list ctx_sbst))])))
            end
          end in
    index(filter_map (fun '(n, c, a) => 
      match construct_cons n c a with 
      | Some x => Some (x,len + List.length c)
      | None => None
      end
    ) d).

Definition nAnon := mkBindAnn nAnon Relevant.

Definition subterm_for_ind
           (refi : inductive)
           (ref   : term)
           (allparams : nat)
           (ntypes : nat) (* number of types in the mutual inductive *)
           (ind   : one_inductive_body)
                  : one_inductive_body
  := let (pai, _) := decompose_prod_assum [] ind.(ind_type) in
    let sort := (tSort (Universe.of_levels (inl PropLevel.lProp))) in
    let npars := getParamCount ind allparams in
    let pars := List.skipn (List.length pai - npars) pai in
    let inds := List.firstn (List.length pai - npars) pai in
    let ninds := List.length inds in
    let aptype1 :=
        mkApps ref ((map (lift0 (2 * ninds)) (to_extended_list pars)) ++
                    (map (lift0 ninds) (to_extended_list inds))) in
    let aptype2 :=
        mkApps ref ((map (lift0 (1 + 2 * ninds)) (to_extended_list pars)) ++
                    (map (lift0 1) (to_extended_list inds))) in
    let renamer name i := (name ++ "_subterm" ++ (string_of_nat i))%string in
    {| ind_name := (ind.(ind_name) ++ "_direct_subterm")%string;
       ind_type  := it_mkProd_or_LetIn
                      pars
                   (it_mkProd_or_LetIn
                      (inds)
                   (it_mkProd_or_LetIn
                      (map_context (lift0 (ninds)) inds)
                   (it_mkProd_or_LetIn
                       [mkdecl nAnon None aptype2; mkdecl nAnon None aptype1]
                       sort)));
       ind_kelim := IntoPropSProp;
       ind_ctors :=List.concat
                     (mapi (fun n '(id', ct, k) => (
                       map (fun '(si, (st, sk)) => (renamer id' si, st, sk))
                       (subterms_for_constructor refi ref ntypes npars ninds ct n k)))
                       ind.(ind_ctors));
      ind_projs := [];
    ind_relevance := Relevant |}.


Definition direct_subterm_for_mutual_ind
            (mind : mutual_inductive_body)
            (ind0 : inductive) (* internal metacoq representation of inductive, part of tInd *)
            (ref  : term) (* reference term for the inductive type, like (tInd {| inductive_mind := "Coq.Init.Datatypes.nat"; inductive_ind := 0 |} []) *)
                  : option mutual_inductive_body
  := let i0 := inductive_ind ind0 in
    let ntypes := List.length (ind_bodies mind) in
    b <- List.nth_error mind.(ind_bodies) i0 ;;
    ret {|
        ind_finite := BasicAst.Finite;
        ind_npars := 0;
        ind_universes := ind_universes mind;
        ind_params := [];
        ind_bodies := [subterm_for_ind ind0 ref mind.(ind_npars) ntypes b];
        ind_variance := None
      |}.

Definition subterm (t : Ast.term)
  : TemplateMonad unit
  := match t with
    | Ast.tInd ind0 _ =>
      decl <- tmQuoteInductive (inductive_mind ind0);;
      tmPrint decl;;
      match (subterm.direct_subterm_for_mutual_ind
               (TemplateToPCUIC.trans_minductive_body decl)
               ind0
               (TemplateToPCUIC.trans t)) with
      | None =>
        tmPrint t;;
        @tmFail unit "Coulnd't construct a subterm"
      | Some d =>
        v <- tmEval lazy (PCUICToTemplate.trans_minductive_body d);;
        tmPrint v;;
        tmMkInductive' v
      end
    | _ =>
      tmPrint t;;
      @tmFail unit " is not an inductive"
    end.
