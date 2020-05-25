{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

-- Orphan instances for {Encode,Decode}Address until we get rid of the
-- Jörmungandr dual support.
{-# OPTIONS_GHC -fno-warn-orphans #-}

-- |
-- Copyright: © 2020 IOHK
-- License: Apache-2.0
--
-- Conversion functions and static chain settings for Shelley.

module Cardano.Wallet.Shelley.Compatibility
    ( Shelley
    , ShelleyBlock

    , NodeVersionData
    , TPraosStandardCrypto

      -- * Chain Parameters
    , mainnetVersionData
    , testnetVersionData

    , mainnetBlockchainParameters

      -- * Genesis
    , emptyGenesis
    , genesisTip

      -- * Conversions
    , toShelleyHash
    , toEpochSize
    , toGenTx
    , toPoint
    , toSlotNo

    , fromBlockNo
    , fromShelleyBlock
    , fromShelleyHash
    , fromPrevHash
    , fromChainHash
    , fromGenesisData
    , fromNetworkMagic
    , fromSlotNo
    , fromTip
    , fromPParams

    , toCardanoTxId
    , toCardanoTxIn
    , toCardanoTxOut
    , toCardanoLovelace
    , toSealed
    ) where

import Prelude

import Cardano.Binary
    ( fromCBOR, serialize' )
import Cardano.Crypto.Hash.Class
    ( Hash (UnsafeHash), getHash )
import Cardano.Slotting.Slot
    ( EpochSize (..) )
import Cardano.Wallet.Api.Types
    ( DecodeAddress (..), EncodeAddress (..) )
import Cardano.Wallet.Primitive.AddressDerivation
    ( NetworkDiscriminant (..), hex )
import Cardano.Wallet.Unsafe
    ( unsafeDeserialiseCbor, unsafeFromHex )
import Control.Arrow
    ( left )
import Data.ByteArray.Encoding
    ( Base (Base16), convertFromBase )
import Data.ByteString
    ( ByteString )
import Data.Coerce
    ( coerce )
import Data.Foldable
    ( toList )
import Data.Maybe
    ( fromMaybe )
import Data.Quantity
    ( Quantity (..) )
import Data.Text
    ( Text )
import Data.Text.Class
    ( TextDecodingError (..) )
import Data.Time.Clock.POSIX
    ( posixSecondsToUTCTime )
import Data.Word
    ( Word16, Word32, Word64 )
import GHC.Stack
    ( HasCallStack )
import Numeric.Natural
    ( Natural )
import Ouroboros.Consensus.BlockchainTime.WallClock.Types
    ( SlotLength (..), getSystemStart )
import Ouroboros.Consensus.Protocol.Abstract
    ( SecurityParam (..) )
import Ouroboros.Consensus.Shelley.Ledger
    ( Crypto, GenTx, ShelleyHash (..) )
import Ouroboros.Consensus.Shelley.Node
    ( ShelleyGenesis (..) )
import Ouroboros.Consensus.Shelley.Protocol.Crypto
    ( TPraosStandardCrypto )
import Ouroboros.Network.Block
    ( BlockNo (..)
    , ChainHash
    , Point (..)
    , SlotNo (..)
    , Tip (..)
    , genesisPoint
    , getLegacyTipBlockNo
    , getTipPoint
    , legacyTip
    )
import Ouroboros.Network.CodecCBORTerm
    ( CodecCBORTerm )
import Ouroboros.Network.Magic
    ( NetworkMagic (..) )
import Ouroboros.Network.NodeToClient
    ( NodeToClientVersionData (..), nodeToClientCodecCBORTerm )
import Ouroboros.Network.Point
    ( WithOrigin (..) )

import qualified Cardano.Api as Cardano
import qualified Cardano.Wallet.Primitive.Types as W
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map.Strict as Map
import qualified Data.Text.Encoding as T
import qualified Ouroboros.Consensus.Shelley.Ledger as O
import qualified Ouroboros.Network.Block as O
import qualified Ouroboros.Network.Point as Point
import qualified Shelley.Spec.Ledger.Address as SL
import qualified Shelley.Spec.Ledger.BlockChain as SL
import qualified Shelley.Spec.Ledger.Coin as SL
import qualified Shelley.Spec.Ledger.PParams as SL
import qualified Shelley.Spec.Ledger.Tx as SL
import qualified Shelley.Spec.Ledger.UTxO as SL

data Shelley

type NodeVersionData =
    (NodeToClientVersionData, CodecCBORTerm Text NodeToClientVersionData)

type ShelleyBlock = O.ShelleyBlock TPraosStandardCrypto

--------------------------------------------------------------------------------
--
-- Chain Parameters


mainnetBlockchainParameters :: W.GenesisBlockParameters
mainnetBlockchainParameters = W.GenesisBlockParameters
    { staticParameters = W.BlockchainParameters
        { getGenesisBlockHash = W.Hash $ unsafeFromHex
            "5f20df933584822601f9e3f8c024eb5eb252fe8cefb24d1317dc3d432e940ebb"
        , getGenesisBlockDate =
            W.StartTime $ posixSecondsToUTCTime 1506203091
        , getSlotLength =
            W.SlotLength 20
        , getEpochLength =
            W.EpochLength 21600
        , getEpochStability =
            Quantity 2160
        , getActiveSlotCoefficient =
            W.ActiveSlotCoefficient 1.0
        }
    , txParameters = W.TxParameters
        { getFeePolicy =
            W.LinearFee (Quantity 155381) (Quantity 43.946) (Quantity 0)
        , getTxMaxSize =
            Quantity 4096
        }
    }

-- NOTE
-- For MainNet and TestNet, we can get away with empty genesis blocks with
-- the following assumption:
--
-- - Users won't ever restore a wallet that has genesis UTxO.
--
-- This assumption is _true_ for any user using HD wallets (sequential or
-- random) which means, any user of cardano-wallet.
emptyGenesis :: W.BlockchainParameters -> W.Block
emptyGenesis bp = W.Block
    { transactions = []
    , delegations  = []
    , header = W.BlockHeader
        { slotId =
            W.SlotId 0 0
        , blockHeight =
            Quantity 0
        , headerHash =
            coerce $ W.getGenesisBlockHash bp
        , parentHeaderHash =
            hashOfNoParent
        }
    }

--------------------------------------------------------------------------------
--
-- Genesis


genesisTip :: Tip (O.ShelleyBlock TPraosStandardCrypto)
genesisTip = legacyTip genesisPoint genesisBlockNo
  where
    -- NOTE: ourobouros-network states that:
    --
    -- There /is/ no block number if we are at genesis
    -- ('genesisBlockNo' is the block number of the first block on the chain).
    -- Usage of this function should be phased out.
    genesisBlockNo = BlockNo 0


--------------------------------------------------------------------------------
--
-- Network Parameters

-- | Settings for configuring a MainNet network client
mainnetVersionData
    :: NodeVersionData
mainnetVersionData =
    ( NodeToClientVersionData
        { networkMagic =
            NetworkMagic $ fromIntegral $ W.getProtocolMagic W.mainnetMagic
        }
    , nodeToClientCodecCBORTerm
    )

-- | Settings for configuring a TestNet network client
testnetVersionData
    :: W.ProtocolMagic
    -> NodeVersionData
testnetVersionData pm =
    ( NodeToClientVersionData
        { networkMagic =
            NetworkMagic $ fromIntegral $ W.getProtocolMagic pm
        }
    , nodeToClientCodecCBORTerm
    )

--------------------------------------------------------------------------------
--
-- Type Conversions

-- | Magic value for the absence of a block.
hashOfNoParent :: W.Hash "BlockHeader"
hashOfNoParent =
    W.Hash . BS.pack $ replicate 32 0

-- fixme: maybe just toShelleyHash = ShelleyHash . CC.unsafeHashFromBytes
toShelleyHash :: W.Hash "BlockHeader" -> ShelleyHash c
toShelleyHash (W.Hash bytes) =
    ShelleyHash $ SL.HashHeader $ UnsafeHash bytes

toEpochSize :: W.EpochLength -> EpochSize
toEpochSize =
    EpochSize . fromIntegral . W.unEpochLength

toPoint
    :: W.Hash "Genesis"
    -> W.EpochLength
    -> W.BlockHeader
    -> Point ShelleyBlock
toPoint genesisH epLength (W.BlockHeader sid _ h _)
  | h == (coerce genesisH) = O.GenesisPoint
  | otherwise = O.Point $ Point.block (toSlotNo epLength sid) (toShelleyHash h)

toSlotNo :: W.EpochLength -> W.SlotId -> SlotNo
toSlotNo epLength =
    SlotNo . W.flatSlot epLength

fromShelleyBlock
    :: W.Hash "Genesis"
    -> W.EpochLength
    -> ShelleyBlock
    -> W.Block
fromShelleyBlock genesisHash epLength blk =
    let
       O.ShelleyBlock (SL.Block (SL.BHeader header _) txSeq) headerHash = blk
       SL.TxSeq txs' = txSeq
       txs = map fromShelleyTx $ toList txs'

    in W.Block
        { header = W.BlockHeader
            { slotId =
                fromSlotNo epLength $ SL.bheaderSlotNo header
            , blockHeight =
                fromBlockNo $ SL.bheaderBlockNo header
            , headerHash =
                fromShelleyHash headerHash
            , parentHeaderHash =
                fromPrevHash (coerce genesisHash) $
                    SL.bheaderPrev header
            }
        , transactions = txs
        , delegations  = []
        }

fromShelleyHash :: ShelleyHash c -> W.Hash "BlockHeader"
fromShelleyHash (ShelleyHash (SL.HashHeader h)) = W.Hash (getHash h)

fromPrevHash
    :: W.Hash "BlockHeader"
    -> SL.PrevHash TPraosStandardCrypto
    -> W.Hash "BlockHeader"
fromPrevHash genesisHash = \case
    SL.GenesisHash -> genesisHash
    SL.BlockHash h -> fromShelleyHash (ShelleyHash h)

fromChainHash
    :: W.Hash "Genesis"
    -> ChainHash ShelleyBlock
    -> W.Hash "BlockHeader"
fromChainHash genesisHash = \case
    O.GenesisHash -> coerce genesisHash
    O.BlockHash h -> fromShelleyHash h

fromSlotNo :: W.EpochLength -> SlotNo -> W.SlotId
fromSlotNo epLength (SlotNo sl) =
    W.fromFlatSlot epLength sl

-- FIXME unsafe conversion (Word64 -> Word32)
fromBlockNo :: BlockNo -> Quantity "block" Word32
fromBlockNo (BlockNo h) =
    Quantity (fromIntegral h)

fromTip
    :: W.Hash "Genesis"
    -> W.EpochLength
    -> Tip ShelleyBlock
    -> W.BlockHeader
fromTip genesisHash epLength tip = case getPoint (getTipPoint tip) of
    Origin -> W.BlockHeader
        { slotId = W.SlotId 0 0
        , blockHeight = Quantity 0
        , headerHash = coerce genesisHash
        , parentHeaderHash = hashOfNoParent
        }
    At blk -> W.BlockHeader
        { slotId = fromSlotNo epLength $ Point.blockPointSlot blk
        , blockHeight = fromBlockNo $ getLegacyTipBlockNo tip
        , headerHash = fromShelleyHash $ Point.blockPointHash blk
        -- TODO
        -- We only use the parentHeaderHash in the
        -- 'Cardano.Wallet.Network.BlockHeaders' chain follower only required for
        -- Jörmungandr, this is therefore useless to have in 'normal' BlockHeader
        --
        -- Yet, since we also serialize these to the database, this requires
        -- some non-trivial changes. Not fixing this right now is also a
        -- possibility.
        , parentHeaderHash = W.Hash "parentHeaderHash - unused in Shelley"
        }

fromSlotLength :: SlotLength -> W.SlotLength
fromSlotLength = W.SlotLength
    . getSlotLength

-- NOTE: Unsafe conversion from Natural -> Word16
fromMaxTxSize :: Natural -> Quantity "byte" Word16
fromMaxTxSize =
    Quantity . fromIntegral

fromPParams :: SL.PParams -> W.TxParameters
fromPParams pp = W.TxParameters
    -- TODO: Why does multiplying with 1000 work?
    { getFeePolicy = W.LinearFee
        (Quantity (1000 * naturalToDouble (SL._minfeeA pp)))
        (Quantity (1000 * fromIntegral (SL._minfeeB pp)))
        (Quantity 0) -- TODO: it's not as simple as this?
    , getTxMaxSize = fromMaxTxSize $ SL._maxTxSize pp
    }
  where
    naturalToDouble :: Natural -> Double
    naturalToDouble = fromIntegral

-- | Convert genesis data into blockchain params and an initial set of UTxO
fromGenesisData
    :: ShelleyGenesis TPraosStandardCrypto
    -> (W.GenesisBlockParameters, [W.TxOut])
fromGenesisData g =
    ( W.GenesisBlockParameters
        { staticParameters = W.BlockchainParameters
            { getGenesisBlockHash =
                -- TODO: There is not yet any agreed upon definition of a
                -- genesis hash for a shelley-only testnet.
                --
                -- For now we use a dummy value.
                W.Hash . BS.pack $ replicate 32 1
            , getGenesisBlockDate =
                W.StartTime . getSystemStart . sgStartTime $ g
            , getSlotLength =
                fromSlotLength . sgSlotLength $ g
            , getEpochLength =
                W.EpochLength . fromIntegral . unEpochSize . sgEpochLength $ g
            , getEpochStability =
                Quantity . fromIntegral . maxRollbacks . sgSecurityParam $ g
            , getActiveSlotCoefficient =
                W.ActiveSlotCoefficient 1.0
            }
        , txParameters = fromPParams . sgProtocolParams $ g
        }
    , map mkTxOut . Map.toList . sgInitialFunds $ g
    )
  where
    mkTxOut (addr, coin) = W.TxOut
        (fromShelleyAddress addr)
        (W.Coin $ fromIntegral coin)
      where

fromNetworkMagic :: NetworkMagic -> W.ProtocolMagic
fromNetworkMagic (NetworkMagic magic) =
    W.ProtocolMagic (fromIntegral magic)

--
-- Txs
--

-- | SealedTx are the result of rightfully constructed shelley transactions so, it
-- is relatively safe to unserialize them from CBOR.
toGenTx :: HasCallStack => W.SealedTx -> GenTx ShelleyBlock
toGenTx = unsafeDeserialiseCbor fromCBOR
    . BL.fromStrict
    . W.getSealedTx

fromShelleyTxId :: SL.TxId crypto -> W.Hash "Tx"
fromShelleyTxId (SL.TxId (UnsafeHash h)) = W.Hash h

fromShelleyTxIn :: SL.TxIn crypto -> W.TxIn
fromShelleyTxIn (SL.TxIn txid ix) =
    W.TxIn (fromShelleyTxId txid) (unsafeCast ix)
  where
    unsafeCast :: Natural -> Word32
    unsafeCast = fromIntegral

fromShelleyTxOut :: Crypto crypto => SL.TxOut crypto -> W.TxOut
fromShelleyTxOut (SL.TxOut addr amount) =
  W.TxOut (fromShelleyAddress addr) (fromShelleyCoin amount)

fromShelleyAddress :: Crypto crypto => SL.Addr crypto -> W.Address
fromShelleyAddress = W.Address
    . SL.serialiseAddr

fromShelleyCoin :: SL.Coin -> W.Coin
fromShelleyCoin (SL.Coin c) = W.Coin $ unsafeCast c
  where
    -- (but probably safe)
    unsafeCast :: Integer -> Word64
    unsafeCast = fromIntegral

-- NOTE: For resolved inputs we have to pass in a dummy value of 0.
fromShelleyTx :: SL.Tx TPraosStandardCrypto -> W.Tx
fromShelleyTx (SL.Tx bod@(SL.TxBody ins outs _ _ _ _ _ _) _ _ _) = W.Tx
    (fromShelleyTxId $ SL.txid bod)
    (map ((,W.Coin 0) . fromShelleyTxIn) (toList ins))
    (map fromShelleyTxOut (toList outs))

-- NOTE: Arguably breaks naming conventions. Perhaps fromCardanoSignedTx instead
toSealed :: SL.Tx TPraosStandardCrypto -> (W.Tx, W.SealedTx)
toSealed tx =
    let
        wtx = fromShelleyTx tx
        sealed = W.SealedTx $ serialize' $ O.mkShelleyTx tx
    in (wtx, sealed)

toCardanoTxId :: W.Hash "Tx" -> Cardano.TxId
toCardanoTxId (W.Hash h) = Cardano.TxId $ UnsafeHash h

toCardanoTxIn :: W.TxIn -> Cardano.TxIn
toCardanoTxIn (W.TxIn tid ix) =
    Cardano.TxIn (toCardanoTxId tid) (fromIntegral ix)

-- NOTE: Only creates Shelley addresses.
toCardanoAddress :: W.Address -> Cardano.Address
toCardanoAddress (W.Address bytes) =
    Cardano.AddressShelley
        . fromMaybe (error "toCardanoAddress: invalid address")
        . SL.deserialiseAddr @TPraosStandardCrypto
        $ bytes

toCardanoLovelace :: W.Coin -> Cardano.Lovelace
toCardanoLovelace (W.Coin c) = Cardano.Lovelace $ safeCast c
  where
    safeCast :: Word64 -> Integer
    safeCast = fromIntegral

toCardanoTxOut :: W.TxOut -> Cardano.TxOut
toCardanoTxOut (W.TxOut addr coin) =
    Cardano.TxOut (toCardanoAddress addr) (toCardanoLovelace coin)

{-------------------------------------------------------------------------------
                      Address Encoding / Decoding
-------------------------------------------------------------------------------}

instance EncodeAddress 'Mainnet where
    encodeAddress = T.decodeUtf8 . hex . W.unAddress

instance EncodeAddress ('Testnet pm) where
    encodeAddress = T.decodeUtf8 . hex . W.unAddress

_decodeAddress :: Text -> Either TextDecodingError W.Address
_decodeAddress x = validateWithLedger =<< W.Address <$> fromHex x
  where
    fromHex :: Text -> Either TextDecodingError ByteString
    fromHex =
        left (const $ TextDecodingError "Unable to decode Address: not valid hex encoding.")
        .  convertFromBase @ByteString @ByteString Base16
        . T.encodeUtf8

    validateWithLedger addr@(W.Address bytes) =
        case SL.deserialiseAddr @TPraosStandardCrypto bytes of
            Just _ -> Right addr
            Nothing -> Left $ TextDecodingError
                "Unable to decode Address: not a well-formed Shelley Address."

instance DecodeAddress 'Mainnet where
    decodeAddress = _decodeAddress

instance DecodeAddress ('Testnet pm) where
    decodeAddress = _decodeAddress
