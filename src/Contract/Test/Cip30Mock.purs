-- | A module for mocking CIP30 wallets.
module Contract.Test.Cip30Mock
  ( module X
  ) where

import Ctl.Internal.Wallet.Cip30Mock
  ( WalletMock(MockFlint, MockGero, MockNami, MockLode)
  , withCip30Mock
  ) as X
