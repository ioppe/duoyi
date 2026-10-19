import '../core/app_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/i18n_date_format.dart';
import '../models/workspace.dart';
import '../providers/auth_provider.dart';
import '../providers/share_provider.dart';
import '../services/api_client.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
import 'login_screen.dart';

class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ShareProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<ShareProvider>();
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;

    if (!auth.state.isLoggedIn) {
      return Scaffold(
        backgroundColor: routeBackground,
        appBar: AppBar(
          title: const Text('共享空间'),
          titleTextStyle: appSecondaryRouteTitleTextStyle(context),
          backgroundColor: routeBackground.withValues(alpha: 0.96),
          surfaceTintColor: Colors.transparent,
        ),
        body: AppSecondaryControlTheme(
          child: EmptyState(
            icon: Icons.group_outlined,
            message: '登录后可以创建共享空间并邀请成员',
            actionLabel: '登录',
            onAction: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: const Text('共享空间'),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        actions: [
          _MentionInboxButton(
            unreadCount: provider.unreadMentionCount,
            onPressed: () => _openMentionInbox(context),
          ),
          IconButton(
            tooltip: '加入空间',
            onPressed: () => _acceptInvite(context),
            icon: const Icon(Icons.qr_code_2),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: provider.loading ? null : () => provider.load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AppSecondaryControlTheme(
        child: RefreshIndicator(
          onRefresh: () => provider.load(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            children: [
              AppSurfaceCard(
                padding: const EdgeInsets.all(16),
                gradient: LinearGradient(
                  colors: [cs.primary.withValues(alpha: 0.12), cs.surface],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.group_outlined, color: cs.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '共享空间',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.normal),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '创建空间后，把待办清单共享给家人、朋友或团队成员。',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.66),
                                ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _createWorkspace(context),
                      icon: const Icon(Icons.add),
                      label: const Text('新建'),
                    ),
                  ],
                ),
              ),
              if (provider.lastError != null) ...[
                const SizedBox(height: 12),
                AppSurfaceCard(
                  padding: const EdgeInsets.all(12),
                  border: Border.all(
                    color: cs.error.withValues(alpha: 0.32),
                    width: 0.45,
                  ),
                  child: Text(
                    provider.lastError!,
                    style: TextStyle(color: cs.error),
                  ),
                ),
              ],
              const AppSectionHeader(
                title: '我的空间',
                subtitle: '拥有者可邀请成员，viewer 只读，editor 可编辑',
              ),
              if (provider.loading)
                const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (provider.workspaces.isEmpty)
                EmptyState(
                  icon: Icons.group_add_outlined,
                  message: '还没有共享空间',
                  actionLabel: '创建空间',
                  onAction: () => _createWorkspace(context),
                )
              else
                ...provider.workspaces.map(
                  (workspace) => _WorkspaceCard(workspace: workspace),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMentionInbox(BuildContext context) async {
    final provider = context.read<ShareProvider>();
    await provider.loadMentionInbox();
    if (!context.mounted) return;
    await showAppModalSheet(
      context: context,
      builder: (sheetContext) => _MentionInboxSheet(
        onOpenMention: (mention) =>
            _openMentionContext(context, sheetContext, mention),
      ),
    );
  }

  Future<void> _openMentionContext(
    BuildContext context,
    BuildContext sheetContext,
    WorkspaceMention mention,
  ) async {
    final provider = context.read<ShareProvider>();
    try {
      if (mention.isUnread) {
        await provider.markMentionRead(mention.id);
      }
      await provider.loadWorkspaceCollaboration(mention.workspaceId);
      if (sheetContext.mounted) {
        Navigator.pop(sheetContext);
      }
      if (!context.mounted) return;
      final workspace = provider.workspaceById(mention.workspaceId);
      await showAppModalSheet(
        context: context,
        builder: (_) => _WorkspaceCollaborationSheet(
          workspace: workspace ?? mention.asWorkspaceFallback,
          focusTargetId: mention.targetId,
          focusCommentId: mention.commentId,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('打开提及失败: ${_shareError(e)}')));
    }
  }

  Future<void> _createWorkspace(BuildContext context) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('新建共享空间'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '空间名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    try {
      await context.read<ShareProvider>().createWorkspace(name);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('创建失败: ${_shareError(e)}')));
    }
  }

  Future<void> _acceptInvite(BuildContext context) async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('加入共享空间'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '邀请码'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('加入'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty || !context.mounted) return;
    try {
      await context.read<ShareProvider>().acceptInvite(code);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已加入共享空间')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加入失败: ${_shareError(e)}')));
    }
  }
}

class _MentionInboxButton extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onPressed;

  const _MentionInboxButton({
    required this.unreadCount,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: unreadCount > 0 ? '$unreadCount 条未读提及' : '@ 提及',
      onPressed: onPressed,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.alternate_email_outlined),
          if (unreadCount > 0)
            Positioned(
              right: -7,
              top: -7,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: cs.error,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: TextStyle(
                    color: cs.onError,
                    fontSize: 9,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MentionInboxSheet extends StatelessWidget {
  final ValueChanged<WorkspaceMention> onOpenMention;

  const _MentionInboxSheet({required this.onOpenMention});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ShareProvider>();
    final mentions = provider.mentions;
    final cs = Theme.of(context).colorScheme;
    return AppModalSheet(
      title: '@ 提及',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mentions.isEmpty)
            _EmptyCollaborationLine(
              icon: Icons.alternate_email_outlined,
              text: '还没有成员提及你',
              color: cs.onSurfaceVariant,
            )
          else
            ...mentions
                .take(20)
                .map(
                  (mention) => _MentionTile(
                    mention: mention,
                    onOpen: () => onOpenMention(mention),
                  ),
                ),
        ],
      ),
    );
  }
}

class _MentionTile extends StatelessWidget {
  final WorkspaceMention mention;
  final VoidCallback onOpen;

  const _MentionTile({required this.mention, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final author = mention.authorName.isEmpty
        ? mention.authorUserId
        : mention.authorName;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: onOpen,
      leading: CircleAvatar(
        radius: 15,
        backgroundColor: mention.isUnread
            ? cs.primary.withValues(alpha: 0.16)
            : cs.surfaceContainerHighest,
        child: Icon(
          mention.isUnread
              ? Icons.alternate_email
              : Icons.alternate_email_outlined,
          size: 16,
          color: mention.isUnread ? cs.primary : cs.onSurfaceVariant,
        ),
      ),
      title: Text(
        mention.body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: mention.isUnread ? cs.onSurface : cs.onSurfaceVariant,
        ),
      ),
      subtitle: Text(
        '$author · ${mention.workspaceName} · ${_formatShortTime(mention.createdAt)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
      trailing: mention.isUnread
          ? FilledButton.tonal(onPressed: onOpen, child: const Text('查看'))
          : const Icon(Icons.chevron_right),
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  final Workspace workspace;

  const _WorkspaceCard({required this.workspace});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final role = workspace.roleFor(auth.state.userId);
    final cs = Theme.of(context).colorScheme;
    final color = workspace.isPrivate ? Colors.blueGrey : cs.primary;
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      border: Border.all(color: color.withValues(alpha: 0.18), width: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  workspace.isPrivate
                      ? Icons.lock_outline
                      : Icons.groups_2_outlined,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workspace.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${workspace.members.length} 位成员 · ${role.label}',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                    if (workspace.members.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _MemberAvatarStack(members: workspace.members),
                    ],
                  ],
                ),
              ),
              if (!workspace.isPrivate) ...[
                IconButton(
                  tooltip: '协作动态',
                  onPressed: () => _openCollaboration(context, workspace),
                  icon: const Icon(Icons.forum_outlined),
                ),
                if (role.canEdit)
                  IconButton(
                    tooltip: '生成邀请码',
                    onPressed: () => _createInvite(context, workspace),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: workspace.members
                .map(
                  (member) => _MemberChip(member: member, workspace: workspace),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _createInvite(BuildContext context, Workspace workspace) async {
    var role = WorkspaceRole.viewer;
    final invite = await showDialog<ShareInvite>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AppDialog(
          title: const Text('生成邀请码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('只读成员'),
                trailing: role == WorkspaceRole.viewer
                    ? Icon(
                        Icons.check,
                        color: Theme.of(ctx).colorScheme.primary,
                      )
                    : null,
                onTap: () => setSt(() => role = WorkspaceRole.viewer),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('可编辑成员'),
                trailing: role == WorkspaceRole.editor
                    ? Icon(
                        Icons.check,
                        color: Theme.of(ctx).colorScheme.primary,
                      )
                    : null,
                onTap: () => setSt(() => role = WorkspaceRole.editor),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final created = await context
                      .read<ShareProvider>()
                      .createInvite(workspace.id, role: role);
                  if (ctx.mounted) Navigator.pop(ctx, created);
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('生成失败: ${_shareError(e)}')),
                  );
                }
              },
              child: const Text('生成'),
            ),
          ],
        ),
      ),
    );
    if (invite == null || !context.mounted) return;
    await Clipboard.setData(ClipboardData(text: invite.code));
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('邀请码已复制'),
        content: SelectableText(
          '${invite.code}\n\n角色：${invite.role.label}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.normal),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  Future<void> _openCollaboration(
    BuildContext context,
    Workspace workspace,
  ) async {
    final provider = context.read<ShareProvider>();
    await provider.loadWorkspaceCollaboration(workspace.id);
    if (!context.mounted) return;
    await showAppModalSheet(
      context: context,
      builder: (_) => _WorkspaceCollaborationSheet(workspace: workspace),
    );
  }
}

class _WorkspaceCollaborationSheet extends StatefulWidget {
  final Workspace workspace;
  final String? focusTargetId;
  final String? focusCommentId;

  const _WorkspaceCollaborationSheet({
    required this.workspace,
    this.focusTargetId,
    this.focusCommentId,
  });

  @override
  State<_WorkspaceCollaborationSheet> createState() =>
      _WorkspaceCollaborationSheetState();
}

class _WorkspaceCollaborationSheetState
    extends State<_WorkspaceCollaborationSheet> {
  final _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ShareProvider>();
    final comments = provider.commentsFor(widget.workspace.id);
    final focusComments =
        widget.focusTargetId == null || widget.focusTargetId!.isEmpty
        ? const <WorkspaceComment>[]
        : provider.commentsForTarget(
            widget.workspace.id,
            widget.focusTargetId!,
          );
    final activities = provider.activitiesFor(widget.workspace.id);
    final leaderboard = provider.leaderboardFor(widget.workspace.id);
    final cs = Theme.of(context).colorScheme;
    return AppModalSheet(
      title: '${widget.workspace.name} · 协作',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _commentCtrl,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.mode_comment_outlined),
              hintText: '写评论，@用户名/邮箱/昵称 可提醒成员',
              suffixIcon: IconButton(
                tooltip: '发送',
                icon: const Icon(Icons.send_outlined),
                onPressed: () => _send(context),
              ),
            ),
            onSubmitted: (_) => _send(context),
          ),
          const SizedBox(height: 12),
          if (widget.focusTargetId != null &&
              widget.focusTargetId!.isNotEmpty) ...[
            _MentionContextBlock(
              targetId: widget.focusTargetId!,
              commentId: widget.focusCommentId ?? '',
              comments: focusComments,
            ),
            const SizedBox(height: 12),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: Text('成员排行榜', style: Theme.of(context).textTheme.labelLarge),
          ),
          const SizedBox(height: 8),
          if (leaderboard.isEmpty)
            _EmptyCollaborationLine(
              icon: Icons.leaderboard_outlined,
              text: '还没有可排行的分配任务',
              color: cs.onSurfaceVariant,
            )
          else
            ...leaderboard
                .take(5)
                .mapIndexed(
                  (index, entry) =>
                      _LeaderboardTile(rank: index + 1, entry: entry),
                ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('最新评论', style: Theme.of(context).textTheme.labelLarge),
          ),
          const SizedBox(height: 8),
          if (comments.isEmpty)
            _EmptyCollaborationLine(
              icon: Icons.forum_outlined,
              text: '还没有评论',
              color: cs.onSurfaceVariant,
            )
          else
            ...comments.take(5).map((comment) => _CommentTile(comment)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('动态流', style: Theme.of(context).textTheme.labelLarge),
          ),
          const SizedBox(height: 8),
          if (activities.isEmpty)
            _EmptyCollaborationLine(
              icon: Icons.history,
              text: '还没有协作动态',
              color: cs.onSurfaceVariant,
            )
          else
            ...activities.take(8).map((activity) => _ActivityTile(activity)),
        ],
      ),
    );
  }

  Future<void> _send(BuildContext context) async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      await context.read<ShareProvider>().createComment(
        widget.workspace.id,
        text,
      );
      if (!context.mounted) return;
      _commentCtrl.clear();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发送失败: ${_shareError(e)}')));
    }
  }
}

String _shareError(Object error) =>
    userVisibleApiError(error, fallbackMessage: '共享空间服务暂不可用，请稍后重试或联系管理员');

class _MentionContextBlock extends StatelessWidget {
  final String targetId;
  final String commentId;
  final List<WorkspaceComment> comments;

  const _MentionContextBlock({
    required this.targetId,
    required this.commentId,
    required this.comments,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final focused = comments
        .where((comment) => comment.id == commentId)
        .toList();
    final visible = focused.isEmpty ? comments.take(3).toList() : focused;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      color: cs.primary.withValues(alpha: 0.06),
      border: Border.all(
        color: cs.primary.withValues(alpha: 0.22),
        width: 0.45,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.alternate_email, size: 16, color: cs.primary),
              Text(
                '提及上下文',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.normal,
                ),
              ),
              AppStatusBadge(label: targetId, color: cs.primary),
            ],
          ),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            Text(
              '这条提及关联到 $targetId，当前页未加载到对应评论。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.66),
              ),
            )
          else
            ...visible.map((comment) => _CommentTile(comment)),
        ],
      ),
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  final int rank;
  final WorkspaceLeaderboardEntry entry;

  const _LeaderboardTile({required this.rank, required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final percent = (entry.completionRate * 100).round();
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          _IdentityAvatar(
            userId: entry.userId,
            username: entry.username,
            role: entry.role,
            radius: 16,
          ),
          Positioned(right: -4, bottom: -3, child: _RankBadge(rank: rank)),
        ],
      ),
      title: Text(
        entry.username.isEmpty ? entry.userId : entry.username,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${entry.role.label} · 分配 ${entry.assigned} · 完成 ${entry.completed}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Text(
        '$percent%',
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.normal,
          fontSize: 13,
        ),
      ),
    );
  }
}

extension _IterableMapIndexed<E> on Iterable<E> {
  Iterable<T> mapIndexed<T>(T Function(int index, E item) convert) sync* {
    var index = 0;
    for (final item in this) {
      yield convert(index, item);
      index++;
    }
  }
}

class _CommentTile extends StatelessWidget {
  final WorkspaceComment comment;

  const _CommentTile(this.comment);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: _IdentityAvatar(
        userId: comment.authorUserId,
        username: comment.authorName,
        radius: 16,
      ),
      title: Text(comment.body, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${comment.authorName.isEmpty ? comment.authorUserId : comment.authorName} · ${_formatShortTime(comment.createdAt)}',
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final WorkspaceActivity activity;

  const _ActivityTile(this.activity);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.bolt_outlined, size: 18),
      title: Text(
        '${activity.actorName} ${activity.label}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _formatShortTime(activity.createdAt),
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}

class _EmptyCollaborationLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _EmptyCollaborationLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

String _formatShortTime(DateTime value) {
  return I18nDateFormat.shortDateTime(AppClock.toLocal(value));
}

class _MemberChip extends StatelessWidget {
  final WorkspaceMember member;
  final Workspace workspace;

  const _MemberChip({required this.member, required this.workspace});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 5, 9, 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.16),
          width: 0.45,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _WorkspaceMemberAvatar(member: member, radius: 12),
          const SizedBox(width: 6),
          Text(
            member.username.isEmpty ? member.userId : member.username,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
          ),
          const SizedBox(width: 5),
          _MemberRoleBadge(role: member.role),
        ],
      ),
    );
  }
}

class _MemberAvatarStack extends StatelessWidget {
  final List<WorkspaceMember> members;

  const _MemberAvatarStack({required this.members});

  @override
  Widget build(BuildContext context) {
    final visible = members.take(5).toList(growable: false);
    final extra = members.length - visible.length;
    return SizedBox(
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * 20,
              top: 0,
              child: _WorkspaceMemberAvatar(
                member: visible[i],
                radius: 14,
                showRoleRing: visible[i].role == WorkspaceRole.owner,
              ),
            ),
          if (extra > 0)
            Positioned(
              left: visible.length * 20,
              top: 0,
              child: _ExtraMemberAvatar(count: extra),
            ),
        ],
      ),
    );
  }
}

class _WorkspaceMemberAvatar extends StatelessWidget {
  final WorkspaceMember member;
  final double radius;
  final bool showRoleRing;

  const _WorkspaceMemberAvatar({
    required this.member,
    required this.radius,
    this.showRoleRing = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _memberColor(
      member.userId.isEmpty ? member.username : member.userId,
    );
    final ringColor = member.role == WorkspaceRole.owner
        ? cs.primary
        : cs.outlineVariant;
    return Tooltip(
      message: '${_memberName(member)} · ${member.role.label}',
      child: Container(
        padding: EdgeInsets.all(showRoleRing ? 1.5 : 1),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.surface,
          border: Border.all(
            color: showRoleRing ? ringColor : cs.surface,
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: color.withValues(alpha: 0.16),
          child: Text(
            _memberInitial(member),
            style: TextStyle(
              fontSize: radius <= 12 ? 10 : 11,
              fontWeight: FontWeight.normal,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _IdentityAvatar extends StatelessWidget {
  final String userId;
  final String username;
  final WorkspaceRole? role;
  final double radius;

  const _IdentityAvatar({
    required this.userId,
    required this.username,
    this.role,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _memberColor(userId.isEmpty ? username : userId);
    return Tooltip(
      message: role == null
          ? _identityName(userId, username)
          : '${_identityName(userId, username)} · ${role!.label}',
      child: Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.surface,
          border: Border.all(color: cs.surface, width: 0.45),
        ),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: color.withValues(alpha: 0.16),
          child: Text(
            _identityInitial(userId, username),
            style: TextStyle(
              fontSize: radius <= 14 ? 10 : 11,
              fontWeight: FontWeight.normal,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;

  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final highlighted = rank <= 3;
    final color = highlighted ? Colors.amber.shade800 : cs.primary;
    return Container(
      width: 17,
      height: 17,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highlighted ? Colors.amber.shade100 : cs.primaryContainer,
        shape: BoxShape.circle,
        border: Border.all(
          color: cs.surface.withValues(alpha: 0.86),
          width: 0.45,
        ),
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.normal,
          color: color,
        ),
      ),
    );
  }
}

class _ExtraMemberAvatar extends StatelessWidget {
  final int count;

  const _ExtraMemberAvatar({required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.surface,
        border: Border.all(color: cs.surface, width: 0.45),
      ),
      child: CircleAvatar(
        radius: 14,
        backgroundColor: cs.surfaceContainerHighest,
        child: Text(
          '+$count',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.normal,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _MemberRoleBadge extends StatelessWidget {
  final WorkspaceRole role;

  const _MemberRoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (role) {
      WorkspaceRole.owner => cs.primary,
      WorkspaceRole.editor => Colors.teal,
      WorkspaceRole.viewer => cs.onSurfaceVariant,
    };
    final icon = switch (role) {
      WorkspaceRole.owner => Icons.workspace_premium_outlined,
      WorkspaceRole.editor => Icons.edit_outlined,
      WorkspaceRole.viewer => Icons.visibility_outlined,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(role.label, style: TextStyle(fontSize: 10.5, color: color)),
        ],
      ),
    );
  }
}

String _memberName(WorkspaceMember member) {
  return _identityName(member.userId, member.username);
}

String _memberInitial(WorkspaceMember member) {
  return _identityInitial(member.userId, member.username);
}

String _identityName(String userId, String username) {
  final name = username.trim();
  if (name.isNotEmpty) return name;
  final id = userId.trim();
  return id.isEmpty ? '成员' : id;
}

String _identityInitial(String userId, String username) {
  final source = _identityName(userId, username);
  if (source.isEmpty) return '?';
  return String.fromCharCode(source.runes.first).toUpperCase();
}

Color _memberColor(String seed) {
  const colors = <Color>[
    Color(0xFF2563EB),
    Color(0xFF059669),
    Color(0xFFDC2626),
    Color(0xFF7C3AED),
    Color(0xFF0891B2),
    Color(0xFF9333EA),
    Color(0xFFCA8A04),
    Color(0xFFDB2777),
  ];
  final value = seed.runes.fold<int>(0, (sum, code) => sum + code);
  return colors[value.abs() % colors.length];
}
