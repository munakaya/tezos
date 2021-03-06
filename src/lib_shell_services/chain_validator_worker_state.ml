(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2018.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

module Request = struct
  type view = Block_hash.t

  let encoding = Block_hash.encoding
  let pp = Block_hash.pp
end

module Event = struct
  type update =
    | Ignored_head
    | Branch_switch
    | Head_incrememt
  type t =
    | Processed_block of
        { request : Request.view ;
          request_status : Worker_types.request_status ;
          update : update ;
          fitness : Fitness.t }
    | Could_not_switch_testchain of error list

  let level = function
    | Processed_block req ->
        begin match req.update with
          | Ignored_head -> Logging.Info
          | Branch_switch | Head_incrememt -> Logging.Notice
        end
    | Could_not_switch_testchain _ -> Logging.Error

  let encoding =
    let open Data_encoding in
    union
      [ case (Tag 0)
          ~title:"Processed_block"
          (obj4
             (req "request" Request.encoding)
             (req "status" Worker_types.request_status_encoding)
             (req "outcome"
                (string_enum [ "ignored", Ignored_head ;
                               "branch", Branch_switch ;
                               "increment", Head_incrememt ]))
             (req "fitness" Fitness.encoding))
          (function
            | Processed_block { request ; request_status ; update ; fitness } ->
                Some (request, request_status, update, fitness)
            | _ -> None)
          (fun (request, request_status, update, fitness) ->
             Processed_block { request ; request_status ; update ; fitness }) ;
        case (Tag 1)
          ~title:"Could_not_switch_testchain"
          RPC_error.encoding
          (function
            | Could_not_switch_testchain err -> Some err
            | _ -> None)
          (fun err -> Could_not_switch_testchain err) ]

  let pp ppf = function
    | Processed_block req ->
        Format.fprintf ppf "@[<v 0>" ;
        begin match req.update with
          | Ignored_head ->
              Format.fprintf ppf
                "Current head is better than %a (fitness %a), we do not switch@,"
          | Branch_switch ->
              Format.fprintf ppf
                "Update current head to %a (fitness %a), changing branch@,"
          | Head_incrememt ->
              Format.fprintf ppf
                "Update current head to %a (fitness %a), same branch@,"
        end
          Request.pp req.request
          Fitness.pp req.fitness ;
        Format.fprintf ppf
          "Pushed: %a, Treated: %a, Completed: %a@]"
          Time.pp_hum req.request_status.pushed
          Time.pp_hum req.request_status.treated
          Time.pp_hum req.request_status.completed
    | Could_not_switch_testchain err ->
        Format.fprintf ppf "@[<v 0>Error while switching test chain:@ %a@]"
          (Format.pp_print_list Error_monad.pp) err

end

module Worker_state = struct
  type view =
    { active_peers : P2p_peer.Id.t list ;
      bootstrapped_peers : P2p_peer.Id.t list ;
      bootstrapped : bool }
  let encoding =
    let open Data_encoding in
    conv
      (fun { bootstrapped ; bootstrapped_peers ; active_peers } ->
         (bootstrapped, bootstrapped_peers, active_peers))
      (fun (bootstrapped, bootstrapped_peers, active_peers) ->
         { bootstrapped ; bootstrapped_peers ; active_peers })
      (obj3
         (req "bootstrapped" bool)
         (req "bootstrapped_peers" (list P2p_peer.Id.encoding))
         (req "active_peers" (list P2p_peer.Id.encoding)))

  let pp ppf { bootstrapped ; bootstrapped_peers ; active_peers } =
    Format.fprintf ppf
      "@[<v 0>Network is%s bootstrapped.@,\
       @[<v 2>Active peers:%a@]@,\
       @[<v 2>Bootstrapped peers:%a@]@]"
      (if bootstrapped then "" else " not yet")
      (fun ppf -> List.iter (Format.fprintf ppf "@,- %a" P2p_peer.Id.pp))
      active_peers
      (fun ppf -> List.iter (Format.fprintf ppf "@,- %a" P2p_peer.Id.pp))
      bootstrapped_peers
end
