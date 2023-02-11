-- | This module contains everything needed for `Contract` testing in Plutip
-- | environment.
module Contract.Test.Plutip
  ( testPlutipContracts
  , module X
  , PlutipTest
  ) where

import Prelude

import Contract.Monad (runContractInEnv) as X
import Contract.Wallet (withKeyWallet) as X
import Ctl.Internal.Plutip.Server
  ( runPlutipContract
  , withPlutipContractEnv
  ) as X
import Ctl.Internal.Plutip.Server (testPlutipContracts) as Server
import Ctl.Internal.Plutip.Types (PlutipConfig)
import Ctl.Internal.Plutip.Types
  ( PlutipConfig
  ) as X
import Ctl.Internal.Test.ContractTest (ContractTest)
import Ctl.Internal.Test.ContractTest (ContractTest) as Server
import Ctl.Internal.Test.ContractTest
  ( noWallet
  , withWallets
  ) as X
import Ctl.Internal.Test.UtxoDistribution
  ( class UtxoDistribution
  , InitialUTxODistribution
  , InitialUTxOs
  , InitialUTxOsWithStakeKey(InitialUTxOsWithStakeKey)
  , UtxoAmount
  , withStakeKey
  ) as X
import Effect.Aff (Aff)
import Mote (MoteT)

-- | Run `Contract`s in tests in a single Plutip instance.
testPlutipContracts
  :: PlutipConfig
  -> MoteT Aff Server.ContractTest Aff Unit
  -> MoteT Aff (Aff Unit) Aff Unit
testPlutipContracts = Server.testPlutipContracts

-- | Type synonym for backwards compatibility.
type PlutipTest = ContractTest
