/*
* Authors: B. Coudray & Q. Berthet
* Date: 04.12.2020
* Description: Lamport Clocks in Promela
*/

#define MAX_PROCESSES 3
#define MAX_MESSAGES_PER_PROCESS 3
//#define DEBUG

typedef Clock {
    int processId;
    int counter;
}

mtype = { lc, request, reply, release, finish } // int => 5, 4, 3, 2, 1

typedef Message {
    Clock clock;
    mtype type;
}

typedef Resource {
    Message messages[MAX_MESSAGES_PER_PROCESS * MAX_PROCESSES * 2];
    int insertPosition;
    int numberOfReleasesReceived;
    int numberOfAccessesToCs;
}

chan channels[MAX_PROCESSES] = [MAX_PROCESSES-1] of {Message};
Clock clocks[MAX_PROCESSES] = {0};
Resource resources[MAX_PROCESSES] = {0};

int criticalSectionCounter = 0

// CLOCK --------------------------
#define CLOCK_ASSIGN(cl, cr) cl.processId = cr.processId -> cl.counter = cr.counter

// MESSAGE ------------------------
#define MESSAGE_ASSIGN(ml, mr) ml.type = mr.type -> CLOCK_ASSIGN(ml.clock, mr.clock)

#define MESSAGE_PRINT(message) printf("Message(%d %d %d)\n", message.type, message.clock.processId, message.clock.counter)

// QUEUE --------------------------
#define QUEUE_HEAD() resources[processId].insertPosition - 1

#define QUEUE_ADD_MESSAGE(message) MESSAGE_ASSIGN(resources[processId].messages[resources[processId].insertPosition], message) -> resources[processId].insertPosition++

// Find the message, remove it from the queue and shift all elements to the left
#define QUEUE_REMOVE_MESSAGE(message) int qrm = 0; \
    bool hasBeenDeleted = false; \
    int qs = QUEUE_HEAD(); \
    for (qrm : 0 .. qs) { \
        if \
        :: message.clock.processId == resources[processId].messages[qrm].clock.processId \
           && message.type == resources[processId].messages[qrm].type \
           && message.clock.counter == resources[processId].messages[qrm].clock.counter -> hasBeenDeleted = true \
        :: hasBeenDeleted -> MESSAGE_ASSIGN(resources[processId].messages[qrm-1], resources[processId].messages[qrm]) \
        fi \
    } \
    resources[processId].insertPosition--

#define QUEUE_PRINT() int qp; \
                      for (qp : 0 .. QUEUE_HEAD()) { \
                          MESSAGE_PRINT(resources[processId].messages[qp]) \
                      }

#define QUEUE_CLEAR() -> resources[processId].messages = {0} -> resources[processId].insertPosition = 0

// LAMPORT --------------------------
#define LAMPORT_MAX() if \
                      :: messageToReceive.clock.counter > clocks[processId].counter -> \
                         clocks[processId].counter = messageToReceive.clock.counter + 1  -> \
                         printf("(R) (%d, %d)\n", processId, clocks[processId].counter) \
                      :: else -> clocks[processId].counter++ -> printf("(R) (%d, %d)\n", processId, clocks[processId].counter) \
                      fi

#define LAMPORT_CAN_ACCESS_TO_CS() int lcatc = 0; /* int i but unique */ \
                                   bool isFoundCs = false; \
                                   Message earliestMessage; \
                                   int numberOfReplyReceived = 0; \
                                   bool access = true; \
                                   int qs = QUEUE_HEAD(); \
                                   do \
                                   :: lcatc <= qs -> \
                                      if \
                                      :: resources[processId].messages[lcatc].type == request && \
                                         !isFoundCs -> MESSAGE_ASSIGN(earliestMessage, resources[processId].messages[lcatc]) -> isFoundCs = true \
                                      :: resources[processId].messages[lcatc].type == request && \
                                         resources[processId].messages[lcatc].clock.processId == processId && \
                                         isFoundCs && resources[processId].messages[lcatc].clock.counter < earliestMessage.clock.counter -> MESSAGE_ASSIGN(earliestMessage, resources[processId].messages[lcatc]) \
                                      :: else -> skip \
                                      fi -> \
                                      -> lcatc++ \
                                   :: else -> lcatc = 0 -> break \
                                   od -> \
                                   do \
                                   :: lcatc <= qs -> \
                                      if \
                                      :: resources[processId].messages[lcatc].type == reply && \
                                         resources[processId].messages[lcatc].clock.processId != processId && \
                                         resources[processId].messages[lcatc].clock.counter > earliestMessage.clock.counter -> numberOfReplyReceived++ \
                                      :: else -> skip \
                                      fi \
                                      -> lcatc++ \
                                   :: else -> break \
                                   od -> \
                                   access = isFoundCs && numberOfReplyReceived >= (MAX_PROCESSES - 1)

#define LAMPORT_SEND_REPLY(sendTo) Message replyMessage; \
                                   replyMessage.type = reply; \
                                   clocks[processId].counter++; \
                                   CLOCK_ASSIGN(replyMessage.clock, clocks[processId]); \
                                   channels[sendTo]!replyMessage

#define LAMPORT_SEND_RELEASE() Message releaseMessage; \
                               releaseMessage.type = release; \
                               clocks[processId].counter++; \
                               CLOCK_ASSIGN(releaseMessage.clock, clocks[processId]); \
                               int lsr; \
                               for (lsr : 0 .. (MAX_PROCESSES-1)) { \
                                   if \
                                   :: lsr != processId -> channels[lsr]!releaseMessage \
                                   :: else -> skip \
                                   fi \
                               }

// EarliestMessage is empty so we assign the first that we found that match with the releaseProcessId
// Then we search for the earliest message
#define LAMPORT_REMOVE_EARLIEST_MESSAGE(releaseProcessId) Message earliestMessage; \
                                          bool isFoundM = false; \
                                          int lrem; \
                                          for (lrem : 0 .. QUEUE_HEAD()) { \
                                              if \
                                              :: !isFoundM && resources[processId].messages[lrem].type == request && \
                                                 resources[processId].messages[lrem].clock.processId == releaseProcessId -> MESSAGE_ASSIGN(earliestMessage, resources[processId].messages[lrem]) -> isFoundM = true \
                                              :: isFoundM && resources[processId].messages[lrem].type == request && \
                                                 resources[processId].messages[lrem].clock.processId == releaseProcessId  && \
                                                 resources[processId].messages[lrem].clock.counter < earliestMessage.clock.counter -> MESSAGE_ASSIGN(earliestMessage, resources[processId].messages[lrem]) \
                                              :: else -> skip \
                                              fi \
                                          } \
                                          if \
                                          :: isFoundM -> QUEUE_REMOVE_MESSAGE(earliestMessage) \
                                          :: else -> skip \
                                          fi

proctype Emission(int processId) {
    int numberOfMessagesSent = 0
    for (numberOfMessagesSent : 0 .. (MAX_MESSAGES_PER_PROCESS-1)) {
        Message requestMessage
        requestMessage.type = request
        atomic {
            clocks[processId].counter++
            CLOCK_ASSIGN(requestMessage.clock, clocks[processId])
            QUEUE_ADD_MESSAGE(requestMessage)
        }
        int i
        for (i : 0 .. (MAX_PROCESSES - 1)) {
            if
            :: i != processId -> channels[i]!requestMessage
                #ifdef DEBUG
                -> printf("P%d has sent a request message to P%d\n", processId, i)
                #endif
            :: else -> skip
            fi
        }
    }

    #ifdef DEBUG
    printf("P%d has finished to send all messages => numberOfMessagesSent = %d\n", processId, numberOfMessagesSent)
    #endif
}

proctype AccessToCriticalSection(int processId) {
    do
    :: if
        // We send MAX_MESSAGES_PER_PROCESS request, so we will acces MAX_MESSAGES_PER_PROCESS to the CS
       :: resources[processId].numberOfAccessesToCs == MAX_MESSAGES_PER_PROCESS -> break
       :: else -> bool canAccess = false
               -> atomic { LAMPORT_CAN_ACCESS_TO_CS() -> canAccess = access; }
               -> if
                  :: canAccess -> int old = criticalSectionCounter -> criticalSectionCounter++ -> assert(old + 1 == criticalSectionCounter)
                     #ifdef DEBUG
                     -> atomic { printf("P%d Queue\n", processId) -> QUEUE_PRINT() }
                     #endif
                     -> printf("P%d : CriticalSectionCounter = %d\n", processId, criticalSectionCounter)
                     -> atomic { LAMPORT_REMOVE_EARLIEST_MESSAGE(processId)
                     -> LAMPORT_SEND_RELEASE()
                     -> resources[processId].numberOfAccessesToCs++ }
                     #ifdef DEBUG
                     -> atomic { printf("P%d Queue\n", processId) -> QUEUE_PRINT() }
                     #endif
                  :: else -> skip
                  fi
        fi
    od
}

proctype Reception(int processId) {
    Message messageToReceive
    do
    :: if
        // We stop to listen any more message when we receive all the release messages.
        :: resources[processId].numberOfReleasesReceived >= MAX_MESSAGES_PER_PROCESS * (MAX_PROCESSES-1) -> break
        :: else -> channels[processId]?messageToReceive
                   -> if
                      :: messageToReceive.type == request -> atomic { LAMPORT_MAX()
                                                          -> QUEUE_ADD_MESSAGE(messageToReceive)
                                                          -> LAMPORT_SEND_REPLY(messageToReceive.clock.processId) }
                          #ifdef DEBUG
                          -> printf("P%d has received a request message from P%d\n", processId, messageToReceive.clock.processId)
                          #endif
                      :: messageToReceive.type == release -> atomic { LAMPORT_MAX()
                                                          -> resources[processId].numberOfReleasesReceived++
                                                          -> LAMPORT_REMOVE_EARLIEST_MESSAGE(messageToReceive.clock.processId) }
                          #ifdef DEBUG
                          -> printf("P%d : Number of releases = %d\n", processId, resources[processId].numberOfReleasesReceived)
                          -> printf("P%d has received a release message from P%d\n", processId, messageToReceive.clock.processId)
                          #endif
                      :: messageToReceive.type == reply -> atomic { LAMPORT_MAX()
                                                        -> QUEUE_ADD_MESSAGE(messageToReceive) }
                      fi
        fi
    od

    #ifdef DEBUG
    printf("P%d has finished to receive all messages\n", processId)
    #endif
}

proctype P1(int processId) {
    clocks[processId].processId = processId
    clocks[processId].counter = 0

    run AccessToCriticalSection(processId)
    run Reception(processId)
    run Emission(processId)
}

init {
    int i;
    for (i : 0 .. (MAX_PROCESSES-1)) {
        run P1(i)
    }
}
