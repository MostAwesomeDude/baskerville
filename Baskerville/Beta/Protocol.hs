module Baskerville.Beta.Protocol where

import Control.Monad.Trans.Class
import qualified Data.ByteString as BS
import Data.IterIO
import Data.IterIO.Atto
import Data.List
import qualified Data.Text as T

import Baskerville.Beta.Packets

data ProtocolStatus = Invalid | Connected | Authenticated | Located
   deriving (Eq, Show)

data ProtocolState = ProtocolState { psStatus :: ProtocolStatus }
    deriving Show

-- | Repeatedly read in packets, process them, and output them.
--   Internally holds the state required for a protocol.
pipeline :: Inum BS.ByteString BS.ByteString IO a
pipeline = mkInumAutoM $ loop $ ProtocolState Connected
    where loop ps = do
            lift $ lift $ putStrLn $ "Top of the pipeline, state " ++ show ps
            packet <- atto parsePacket
            lift $ lift $ putStrLn $ "Parsed a packet: " ++ show packet
            let (state, packets) = processPacket ps packet
            lift $ lift $ putStrLn $ "Processed a packet, state " ++ show state
            _ <- ifeed $ BS.concat $ map buildPacket $ takeWhile invalidPred packets
            lift $ lift $ putStrLn "Fed the iteratee!"
            _ <- if psStatus state == Invalid then idone else return ()
            lift $ lift $ putStrLn "Getting ready to loop!"
            loop state

socketHandler :: (Iter BS.ByteString IO a, Onum BS.ByteString IO a) -> IO ()
socketHandler (output, input) = do
    putStrLn "Starting pipeline..."
    _ <- input |$ pipeline .| output
    putStrLn "Finished pipeline!"

-- | A helper for iterating over an infinite packet stream and returning
--   another infinite packet stream in return. When in doubt, use this.
processPacketStream :: [Packet] -> [Packet]
processPacketStream packets =
    let state = ProtocolState Connected
        mapper = concat . snd . mapAccumL processPacket state
    in takeWhile invalidPred $ mapper packets

-- | Determine whether a packet is an InvalidPacket.
--   This is used as a predicate for determining when to finish the packet
--   stream; InvalidPacket is always the end of the line. Note that the values
--   are inverted since this will be passed to takeWhile.
invalidPred :: Packet -> Bool
invalidPred InvalidPacket = False
invalidPred _ = True

-- | The main entry point for a protocol.
--   Run this function over a packet and receive zero or more packets in
--   reply. This function should be provided with state so that it can
--   process consecutive packets.
processPacket :: ProtocolState -> Packet -> (ProtocolState, [Packet])
processPacket ps PollPacket =
    (ps { psStatus = Invalid },
     [ErrorPacket $ T.pack "Baskerville§0§1", InvalidPacket])
processPacket ps _ = (ps { psStatus = Invalid }, [InvalidPacket])