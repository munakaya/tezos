(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2016.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

open Proto_alpha
open Alpha_context

type t =
  | B of Block.t
  | I of Incremental.t

let branch = function
  | B b -> b.hash
  | I i -> (Incremental.predecessor i).hash

let level = function
  | B b -> b.header.shell.level
  | I i -> (Incremental.level i)

let get_level ctxt =
  level ctxt
  |> Raw_level.of_int32
  |> Alpha_environment.wrap_error
  |> Lwt.return

let rpc_ctxt = object
  method call_proto_service0 :
    'm 'q 'i 'o.
    ([< RPC_service.meth ] as 'm, Alpha_environment.RPC_context.t, Alpha_environment.RPC_context.t, 'q, 'i, 'o) RPC_service.t ->
    t -> 'q -> 'i -> 'o tzresult Lwt.t =
    fun s pr q i ->
      match pr with
      | B b -> Block.rpc_ctxt#call_proto_service0 s b q i
      | I b -> Incremental.rpc_ctxt#call_proto_service0 s b q i
  method call_proto_service1 :
    'm 'a 'q 'i 'o.
    ([< RPC_service.meth ] as 'm, Alpha_environment.RPC_context.t, Alpha_environment.RPC_context.t * 'a, 'q, 'i, 'o) RPC_service.t ->
    t -> 'a -> 'q -> 'i -> 'o tzresult Lwt.t =
    fun s pr a q i ->
      match pr with
      | B bl -> Block.rpc_ctxt#call_proto_service1 s bl a q i
      | I bl -> Incremental.rpc_ctxt#call_proto_service1 s bl a q i
  method call_proto_service2 :
    'm 'a 'b 'q 'i 'o.
    ([< RPC_service.meth ] as 'm, Alpha_environment.RPC_context.t, (Alpha_environment.RPC_context.t * 'a) * 'b, 'q, 'i, 'o) RPC_service.t ->
    t -> 'a -> 'b -> 'q -> 'i -> 'o tzresult Lwt.t =
    fun s pr a b q i ->
      match pr with
      | B bl -> Block.rpc_ctxt#call_proto_service2 s bl a b q i
      | I bl -> Incremental.rpc_ctxt#call_proto_service2 s bl a b q i
  method call_proto_service3 :
    'm 'a 'b 'c 'q 'i 'o.
    ([< RPC_service.meth ] as 'm, Alpha_environment.RPC_context.t, ((Alpha_environment.RPC_context.t * 'a) * 'b) * 'c, 'q, 'i, 'o) RPC_service.t ->
    t -> 'a -> 'b -> 'c -> 'q -> 'i -> 'o tzresult Lwt.t =
    fun s pr a b c q i ->
      match pr with
      | B bl -> Block.rpc_ctxt#call_proto_service3 s bl a b c q i
      | I bl -> Incremental.rpc_ctxt#call_proto_service3 s bl a b c q i
end

let get_endorsers ctxt =
  Alpha_services.Delegate.Endorsing_rights.get rpc_ctxt ctxt

let get_endorser ctxt slot =
  Alpha_services.Delegate.Endorsing_rights.get
    rpc_ctxt ctxt >>=? fun endorsers ->
  try return (List.find (fun {Alpha_services.Delegate.Endorsing_rights.slots} -> List.mem slot slots) endorsers).delegate
  with _ ->
    failwith "Failed to lookup endorsers for ctxt %a, slot %d."
      Block_hash.pp_short (branch ctxt) slot

let get_bakers ctxt =
  Alpha_services.Delegate.Baking_rights.get
    ~max_priority:256
    rpc_ctxt ctxt >>=? fun bakers ->
  return (List.map
            (fun p -> p.Alpha_services.Delegate.Baking_rights.delegate)
            bakers)

let get_constants b =
  Alpha_services.Constants.all rpc_ctxt b

module Contract = struct

  let pkh c = Alpha_context.Contract.is_implicit c |> function
    | Some p -> return p
    | None -> failwith "pkh: only for implicit contracts"

  type balance_kind = Main | Deposit | Fees | Rewards

  let balance ?(kind = Main) ctxt contract =
    begin match kind with
      | Main ->
          Alpha_services.Contract.balance rpc_ctxt ctxt contract
      | _ ->
          match Alpha_context.Contract.is_implicit contract with
          | None ->
              invalid_arg
                "get_balance: no frozen accounts for an originated contract."
          | Some pkh ->
              Alpha_services.Delegate.frozen_balance_by_cycle
                rpc_ctxt ctxt pkh >>=? fun map ->
              Lwt.return @@
              Cycle.Map.fold
                (fun _cycle { Delegate.deposit ; fees ; rewards } acc ->
                   acc >>?fun acc ->
                   match kind with
                   | Deposit -> Test_tez.Tez.(acc +? deposit)
                   | Fees -> Test_tez.Tez.(acc +? fees)
                   | Rewards ->  Test_tez.Tez.(acc +? rewards)
                   | _ -> assert false)
                map
                (Ok Tez.zero)
    end

  let counter ctxt contract =
    Alpha_services.Contract.counter rpc_ctxt ctxt contract

  let manager ctxt contract =
    Alpha_services.Contract.manager rpc_ctxt ctxt contract >>=? fun pkh ->
    Account.find pkh

  let is_manager_key_revealed ctxt contract =
    Alpha_services.Contract.manager_key rpc_ctxt ctxt contract >>=? fun (_, res) ->
    return (res <> None)

end

let init
    ?(slow=false)
    ?endorsers_per_block
    ?commitments
    n =
  let accounts = Account.generate_accounts n in
  let contracts = List.map (fun (a, _) ->
      Alpha_context.Contract.implicit_contract Account.(a.pkh)) accounts in
  begin
    if slow then
      Block.genesis
        ?endorsers_per_block
        ?commitments
        accounts
    else
      Block.genesis
        ~blocks_per_cycle:32l
        ~blocks_per_commitment:4l
        ~blocks_per_roll_snapshot:8l
        ?endorsers_per_block
        ?commitments
        accounts
  end >>=? fun blk ->
  return (blk, contracts)
