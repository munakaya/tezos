(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2018.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

include Bigstring

include EndianBigstring.BigEndian
module LE = EndianBigstring.LittleEndian

let make sz c =
  let buf = create sz in
  fill buf c ;
  buf

let to_hex t =
  Hex.of_cstruct (Cstruct.of_bigarray t)

let of_hex hex =
  Cstruct.to_bigarray (Hex.to_cstruct hex)

let pp_hex ppf s =
  let `Hex hex = to_hex s in
  Format.pp_print_string ppf hex

let cut ?(copy=false) sz bytes =
  let length = length bytes in
  if length <= sz then
    [bytes] (* if the result fits in the given sz *)
  else
    let may_copy = if copy then Bigstring.copy else fun t -> t in
    let nb_full = length / sz in (* nb of blocks of size sz *)
    let sz_full = nb_full * sz in (* size of the full part *)
    let acc = (* eventually init acc with a non-full block *)
      if sz_full = length then []
      else [may_copy (sub bytes sz_full (length - sz_full))]
    in
    let rec split_full_blocks curr_upper_limit acc =
      let start = curr_upper_limit - sz in
      assert (start >= 0);
      (* copy the block [ start, curr_upper_limit [ of size sz *)
      let acc = (may_copy (sub bytes start sz)) :: acc in
      if start = 0 then acc else split_full_blocks start acc
    in
    split_full_blocks sz_full acc

include Compare.Make(struct
    type nonrec t = t
    let compare = Bigstring.compare
  end)
