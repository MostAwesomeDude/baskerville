module Main where

import qualified Data.ByteString as BS
import Control.Concurrent
import Control.Exception hiding (catch)
import Control.Monad
import Network hiding (accept)
import Network.Socket (accept)
import Data.IterIO
import Data.IterIO.Atto

import Baskerville.Beta.Packets
import Baskerville.Beta.Protocol

parser :: Monad m => Iter BS.ByteString m [Packet]
parser = atto parsePackets

builder :: Monad m => [Packet] -> Onum BS.ByteString m a
builder packets = enumPure (BS.concat $ map buildPacket packets)

-- | Repeatedly read in packets, process them, and output them.
--   Internally holds the state required for a protocol.
pipeline :: Monad m => Inum BS.ByteString BS.ByteString m a
pipeline = mkInumAutoM $ loop $ ProtocolState ()
    where loop ps = do
            packet <- atto parsePacket
            let (state, packets) = processPacket ps packet
            _ <- ifeed $ BS.concat $ map buildPacket packets
            loop state

handler :: (Iter BS.ByteString IO a, Onum BS.ByteString IO a) -> IO a
handler (output, input) = do
    putStrLn "Starting pipeline..."
    input |$ pipeline .| output

fork :: Socket -> IO ()
fork listener = forever $ do
    (sock, addr) <- accept listener
    putStrLn $ "Accepting connection from " ++ show addr ++ "..."
    pair <- iterStream sock
    _ <- forkIO (handler pair)
    return ()

-- | Guard an opened socket so that it will always close during cleanup.
--   This can and should be used in place of listenOn.
withListenOn :: PortID -> (Socket -> IO a) -> IO a
withListenOn port = bracket (listenOn port) sClose 

startServer :: IO ()
startServer = withListenOn (PortNumber 12321) fork

main :: IO ()
main = withSocketsDo startServer
