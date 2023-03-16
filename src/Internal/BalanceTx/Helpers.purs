module Ctl.Internal.BalanceTx.Helpers
  ( _body'
  , _transaction'
  , _unbalancedTx
  ) where

import Prelude

import Ctl.Internal.Cardano.Types.Transaction
  ( Redeemer
  , Transaction
  , TxBody
  , _body
  )
import Ctl.Internal.Types.ScriptLookups
  ( UnattachedUnbalancedTx(UnattachedUnbalancedTx)
  )
import Ctl.Internal.Types.Transaction (TransactionInput)
import Ctl.Internal.Types.UnbalancedTransaction (UnbalancedTx, _transaction)
import Data.Lens (Lens', lens')
import Data.Lens.Getter ((^.))
import Data.Lens.Setter ((%~), (.~))
import Data.Maybe (Maybe)
import Data.Tuple.Nested (type (/\), (/\))

_unbalancedTx :: Lens' UnattachedUnbalancedTx UnbalancedTx
_unbalancedTx = lens' \(UnattachedUnbalancedTx rec@{ unbalancedTx }) ->
  unbalancedTx /\
    \ubTx -> UnattachedUnbalancedTx rec { unbalancedTx = ubTx }

_transaction' :: Lens' UnattachedUnbalancedTx Transaction
_transaction' = lens' \unattachedTx ->
  unattachedTx ^. _unbalancedTx <<< _transaction /\
    \tx -> unattachedTx # _unbalancedTx %~ (_transaction .~ tx)

_body' :: Lens' UnattachedUnbalancedTx TxBody
_body' = lens' \unattachedTx ->
  unattachedTx ^. _transaction' <<< _body /\
    \txBody -> unattachedTx # _transaction' %~ (_body .~ txBody)
