{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}

module Zero.Chat.Operators.Presets where

import Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as L
import Zero.Chat.Library.Internal (zeroChatImage)
import Zero.Chat.Operators
import Zero.Chat.Protocol (mkRelayProfile)
import Zero.Messaging.Agent.Env.SQLite (ServerRoles (..), allRoles)
import Zero.Messaging.Agent.Store.Entity
import Zero.Messaging.Encoding.String
import Zero.Messaging.Protocol (ProtocolType (..), SMPServer)

operatorZero :: NewServerOperator
operatorZero =
  ServerOperator
    { operatorId = DBNewEntity,
      operatorTag = Just OTZero,
      tradeName = "Zero NA",
      legalName = Just "Zero",
      serverDomains = ["simpl.global"],
      conditionsAcceptance = CARequired Nothing,
      enabled = True,
      smpRoles = allRoles,
      xftpRoles = allRoles
    }

operatorFlux :: NewServerOperator
operatorFlux =
  ServerOperator
    { operatorId = DBNewEntity,
      operatorTag = Just OTFlux,
      tradeName = "Zero EU",
      legalName = Just "Simpl LLC",
      serverDomains = ["eu.simpl.global"],
      conditionsAcceptance = CARequired Nothing,
      enabled = True,
      smpRoles = ServerRoles {storage = False, proxy = True, names = True},
      xftpRoles = allRoles
    }

allPresetServers :: NonEmpty SMPServer
allPresetServers = enabledZeroSMPServers <> disabledZeroSMPServers <> fluxSMPServers_
  <> ["smp://8Af90NX2TTkKEJAF1RCg69P_Odg2Z-6_J6DOKUqK3rQ=@smp7.simpl.global,dbxqutskmmbkbrs7ofi7pmopeyhgi5cxbjbh4ummgmep4r6bz4cbrcid.onion"]

zeroChatSMPServers :: [NewUserServer 'PSMP]
zeroChatSMPServers =
  map (presetServer' True) (L.toList enabledZeroSMPServers)
    <> map (presetServer' False) (L.toList disabledZeroSMPServers)

enabledZeroSMPServers :: NonEmpty SMPServer
enabledZeroSMPServers =
  [ "smp://pJ5gVPxIPmCXflOJ7W7avwpDka1mEHcNaHEqcAwBx0c=@zerorelay.simpl.global:5223",
    "smp://TctoW4I8Pkb7i547zF_zX4OEj0EG1GEFYfh1QAPD3Ok=@zeroeu.simpl.global:5223"
  ]

disabledZeroSMPServers :: NonEmpty SMPServer
disabledZeroSMPServers =
  [ "smp://0YuTwO05YJWS8rkjn9eLJDjQhFKvIYd8d4xG8X1blIU=@smp8.simpl.global,beccx4yfxxbvyhqypaavemqurytl6hozr47wfc7uuecacjqdvwpw2xid.onion",
    "smp://SkIkI6EPd2D63F4xFKfHk7I1UGZVNn6k1QWZ5rcyr6w=@smp9.simpl.global,jssqzccmrcws6bhmn77vgmhfjmhwlyr3u7puw4erkyoosywgl67slqqd.onion",
    "smp://6iIcWT_dF2zN_w5xzZEY7HI2Prbh3ldP07YTyDexPjE=@smp10.simpl.global,rb2pbttocvnbrngnwziclp2f4ckjq65kebafws6g4hy22cdaiv5dwjqd.onion",
    "smp://1OwYGt-yqOfe2IyVHhxz3ohqo3aCCMjtB-8wn4X_aoY=@smp11.simpl.global,6ioorbm6i3yxmuoezrhjk6f6qgkc4syabh7m3so74xunb5nzr4pwgfqd.onion",
    "smp://UkMFNAXLXeAAe0beCa4w6X_zp18PwxSaSjY17BKUGXQ=@smp12.simpl.global,ie42b5weq7zdkghocs3mgxdjeuycheeqqmksntj57rmejagmg4eor5yd.onion",
    "smp://enEkec4hlR3UtKx2NMpOUK_K4ZuDxjWBO1d9Y4YXVaA=@smp14.simpl.global,aspkyu2sopsnizbyfabtsicikr2s4r3ti35jogbcekhm3fsoeyjvgrid.onion",
    "smp://h--vW7ZSkXPeOUpfxlFGgauQmXNFOzGoizak7Ult7cw=@smp15.simpl.global,oauu4bgijybyhczbnxtlggo6hiubahmeutaqineuyy23aojpih3dajad.onion",
    "smp://hejn2gVIqNU6xjtGM3OwQeuk8ZEbDXVJXAlnSBJBWUA=@smp16.simpl.global,p3ktngodzi6qrf7w64mmde3syuzrv57y55hxabqcq3l5p6oi7yzze6qd.onion",
    "smp://ZKe4uxF4Z_aLJJOEsC-Y6hSkXgQS5-oc442JQGkyP8M=@smp17.simpl.global,ogtwfxyi3h2h5weftjjpjmxclhb5ugufa5rcyrmg7j4xlch7qsr5nuqd.onion",
    "smp://PtsqghzQKU83kYTlQ1VKg996dW4Cw4x_bvpKmiv8uns=@smp18.simpl.global,lyqpnwbs2zqfr45jqkncwpywpbtq7jrhxnib5qddtr6npjyezuwd3nqd.onion",
    "smp://N_McQS3F9TGoh4ER0QstUf55kGnNSd-wXfNPZ7HukcM=@smp19.simpl.global,i53bbtoqhlc365k6kxzwdp5w3cdt433s7bwh3y32rcbml2vztiyyz5id.onion",
    "smp://u2dS9sG8nMNURyZwqASV4yROM28Er0luVTx5X1CsMrU=@smp4.simpl.global,o5vmywmrnaxalvz6wi3zicyftgio6psuvyniis6gco6bp6ekl4cqj4id.onion",
    "smp://hpq7_4gGJiilmz5Rf-CswuU5kZGkm_zOIooSw6yALRg=@smp5.simpl.global,jjbyvoemxysm7qxap7m5d5m35jzv5qq6gnlv7s4rsn7tdwwmuqciwpid.onion",
    "smp://PQUV2eL0t7OStZOoAsPEV2QYWt4-xilbakvGUGOItUo=@smp6.simpl.global,bylepyau3ty4czmn77q4fglvperknl4bi2eb2fdy2bh4jxtf32kf73yd.onion"
  ]

zeroChatRelays :: [NewUserChatRelay]
zeroChatRelays =
  [ presetChatRelay True (mkRelayProfile "Zero Relay 1" $ Just zeroChatImage) ["simpl.global"] (either error id $ strDecode "https://smp5.simpl.global/r#Fp5RWXkiRFg-hgcDwC2v-MWnPfvEf42RgCqREntW0mw"),
    presetChatRelay True (mkRelayProfile "Zero Relay 2" $ Just zeroChatImage) ["simpl.global"] (either error id $ strDecode "https://smp6.simpl.global/r#_qlQfogHGDJ8MAF2wKmkglRBM-xHR142gDJstKiGRQQ"),
    presetChatRelay True (mkRelayProfile "Zero Relay 3" $ Just zeroChatImage) ["simpl.global"] (either error id $ strDecode "https://smp4.simpl.global/r#yxNOMJcry5jMTRPEBVtGBATYaKeoRIsZRBPIDLx7x6M")
  ]

fluxSMPServers :: [NewUserServer 'PSMP]
fluxSMPServers = map (presetServer' True) (L.toList fluxSMPServers_)

fluxSMPServers_ :: NonEmpty SMPServer
fluxSMPServers_ =
  [ "smp://xQW_ufMkGE20UrTlBl8QqceG1tbuylXhr9VOLPyRJmw=@smp1.eu.simpl.global,qb4yoanyl4p7o33yrknv4rs6qo7ugeb2tu2zo66sbebezs4cpyosarid.onion",
    "smp://LDnWZVlAUInmjmdpQQoIo6FUinRXGe0q3zi5okXDE4s=@smp2.eu.simpl.global,yiqtuh3q4x7hgovkomafsod52wvfjucdljqbbipg5sdssnklgongxbqd.onion",
    "smp://1jne379u7IDJSxAvXbWb_JgoE7iabcslX0LBF22Rej0=@smp3.eu.simpl.global,a5lm4k7ufei66cdck6fy63r4lmkqy3dekmmb7jkfdm5ivi6kfaojshad.onion",
    "smp://xmAmqj75I9mWrUihLUlI0ZuNLXlIwFIlHRq5Pb6cHAU=@smp4.eu.simpl.global,qpcz2axyy66u26hfdd2e23uohcf3y6c36mn7dcuilcgnwjasnrvnxjqd.onion",
    "smp://rWvBYyTamuRCBYb_KAn-nsejg879ndhiTg5Sq3k0xWA=@smp5.eu.simpl.global,4ao347qwiuluyd45xunmii4skjigzuuox53hpdsgbwxqafd4yrticead.onion",
    "smp://PN7-uqLBToqlf1NxHEaiL35lV2vBpXq8Nj8BW11bU48=@smp6.eu.simpl.global,hury6ot3ymebbr2535mlp7gcxzrjpc6oujhtfxcfh2m4fal4xw5fq6qd.onion"
  ]

fluxXFTPServers :: [NewUserServer 'PXFTP]
fluxXFTPServers =
  map
    (presetServer True)
    [ "xftp://92Sctlc09vHl_nAqF2min88zKyjdYJ9mgxRCJns5K2U=@xftp1.eu.simpl.global,apl3pumq3emwqtrztykyyoomdx4dg6ysql5zek2bi3rgznz7ai3odkid.onion",
      "xftp://YBXy4f5zU1CEhnbbCzVWTNVNsaETcAGmYqGNxHntiE8=@xftp2.eu.simpl.global,c5jjecisncnngysah3cz2mppediutfelco4asx65mi75d44njvua3xid.onion",
      "xftp://ARQO74ZSvv2OrulRF3CdgwPz_AMy27r0phtLSq5b664=@xftp3.eu.simpl.global,dc4mohiubvbnsdfqqn7xhlhpqs5u4tjzp7xpz6v6corwvzvqjtaqqiqd.onion",
      "xftp://ub2jmAa9U0uQCy90O-fSUNaYCj6sdhl49Jh3VpNXP58=@xftp4.eu.simpl.global,4qq5pzier3i4yhpuhcrhfbl6j25udc4czoyascrj4yswhodhfwev3nyd.onion",
      "xftp://Rh19D5e4Eez37DEE9hAlXDB3gZa1BdFYJTPgJWPO9OI=@xftp5.eu.simpl.global,q7itltdn32hjmgcqwhow4tay5ijetng3ur32bolssw32fvc5jrwvozad.onion",
      "xftp://0AznwoyfX8Od9T_acp1QeeKtxUi676IBIiQjXVwbdyU=@xftp6.eu.simpl.global,upvzf23ou6nrmaf3qgnhd6cn3d74tvivlmz3p7wdfwq6fhthjrjiiqid.onion"
    ]
