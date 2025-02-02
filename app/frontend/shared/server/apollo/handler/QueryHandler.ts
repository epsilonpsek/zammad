// Copyright (C) 2012-2023 Zammad Foundation, https://zammad-foundation.org/
/* eslint-disable no-use-before-define */

import type { Ref, WatchStopHandle } from 'vue'
import { watch } from 'vue'
import type {
  ApolloQueryResult,
  FetchMoreOptions,
  FetchMoreQueryOptions,
  ObservableQuery,
  OperationVariables,
  SubscribeToMoreOptions,
} from '@apollo/client/core'
import type {
  OperationQueryOptionsReturn,
  OperationQueryResult,
  WatchResultCallback,
} from '@shared/types/server/apollo/handler'
import type { ReactiveFunction } from '@shared/types/utils'
import type { UseQueryOptions, UseQueryReturn } from '@vue/apollo-composable'
import { useApolloClient } from '@vue/apollo-composable'
import BaseHandler from './BaseHandler'

export default class QueryHandler<
  TResult = OperationQueryResult,
  TVariables extends OperationVariables = OperationVariables,
> extends BaseHandler<
  TResult,
  TVariables,
  UseQueryReturn<TResult, TVariables>
> {
  private firstResultLoaded = false

  private lastCancel: (() => void) | null = null

  public cancel() {
    this.lastCancel?.()
  }

  public async query(variables?: TVariables) {
    this.cancel()
    const node = this.operationResult.document.value
    const { client } = useApolloClient()
    const aborter =
      typeof AbortController !== 'undefined' ? new AbortController() : null
    this.lastCancel = () => aborter?.abort()
    try {
      return await client.query<TResult, TVariables>({
        query: node,
        variables,
        context: {
          fetchOptions: {
            signal: aborter?.signal,
          },
        },
      })
    } finally {
      this.lastCancel = null
    }
  }

  public options(): OperationQueryOptionsReturn<TResult, TVariables> {
    return this.operationResult.options
  }

  public result(): Ref<TResult | undefined> {
    return this.operationResult.result
  }

  public watchQuery(): Ref<
    ObservableQuery<TResult, TVariables> | null | undefined
  > {
    return this.operationResult.query
  }

  public subscribeToMore<
    TSubscriptionVariables = TVariables,
    TSubscriptionData = TResult,
  >(
    options:
      | SubscribeToMoreOptions<
          TResult,
          TSubscriptionVariables,
          TSubscriptionData
        >
      | ReactiveFunction<
          SubscribeToMoreOptions<
            TResult,
            TSubscriptionVariables,
            TSubscriptionData
          >
        >,
  ): void {
    return this.operationResult.subscribeToMore(options)
  }

  public fetchMore(
    options: FetchMoreQueryOptions<TVariables, TResult> &
      FetchMoreOptions<TResult, TVariables>,
  ): Promise<Maybe<TResult>> {
    return new Promise((resolve, reject) => {
      const fetchMore = this.operationResult.fetchMore(options)

      if (!fetchMore) {
        resolve(null)
        return
      }

      fetchMore
        .then((result) => {
          resolve(result.data)
        })
        .catch(() => {
          reject(this.operationError().value)
        })
    })
  }

  public refetch(variables?: TVariables): Promise<Maybe<TResult>> {
    return new Promise((resolve, reject) => {
      const refetch = this.operationResult.refetch(variables)

      if (!refetch) {
        resolve(null)
        return
      }

      refetch
        .then((result) => {
          resolve(result.data)
        })
        .catch(() => {
          reject(this.operationError().value)
        })
    })
  }

  public load(
    variables?: TVariables,
    options?: UseQueryOptions<TResult, TVariables>,
  ): void {
    const operation = this.operationResult as unknown as {
      load?: (
        document?: unknown,
        variables?: TVariables,
        options?: UseQueryOptions<TResult, TVariables>,
      ) => void
    }

    if (typeof operation.load !== 'function') {
      return
    }

    operation.load(undefined, variables, options)
  }

  public start(): void {
    this.operationResult.start()
  }

  public stop(): void {
    this.firstResultLoaded = false
    this.operationResult.stop()
  }

  public abort() {
    this.operationResult.stop()
    this.operationResult.start()
  }

  public async onLoaded(
    triggerPossibleRefetch = false,
  ): Promise<Maybe<TResult>> {
    if (this.firstResultLoaded && triggerPossibleRefetch) {
      return this.refetch()
    }

    return new Promise((resolve, reject) => {
      let errorUnsubscribe!: () => void
      let resultUnsubscribe!: () => void

      const onFirstResultLoaded = () => {
        this.firstResultLoaded = true
        resultUnsubscribe()
        errorUnsubscribe()
      }

      resultUnsubscribe = watch(this.result(), (result) => {
        // After a variable change, the result will be reseted.
        if (result === undefined) return null

        // Remove the watchers again after the promise was resolved.
        onFirstResultLoaded()
        return resolve(result || null)
      })

      errorUnsubscribe = watch(this.operationError(), (error) => {
        onFirstResultLoaded()
        return reject(error)
      })
    })
  }

  public loadedResult(triggerPossibleRefetch = false): Promise<Maybe<TResult>> {
    return this.onLoaded(triggerPossibleRefetch)
      .then((data: Maybe<TResult>) => data)
      .catch((error) => error)
  }

  public watchOnceOnResult(callback: WatchResultCallback<TResult>) {
    const watchStopHandle = watch(
      this.result(),
      (result) => {
        if (!result) {
          return
        }
        callback(result)
        watchStopHandle()
      },
      {
        // Needed for when the component is mounted after the first mount, in this case
        // result will already contain the data and the watch will otherwise not be triggered.
        immediate: true,
      },
    )
  }

  public watchOnResult(
    callback: WatchResultCallback<TResult>,
  ): WatchStopHandle {
    return watch(
      this.result(),
      (result) => {
        if (!result) {
          return
        }
        callback(result)
      },
      {
        // Needed for when the component is mounted after the first mount, in this case
        // result will already contain the data and the watch will otherwise not be triggered.
        immediate: true,
      },
    )
  }

  public onResult(
    callback: (result: ApolloQueryResult<TResult>) => void,
  ): void {
    this.operationResult.onResult(callback)
  }
}
