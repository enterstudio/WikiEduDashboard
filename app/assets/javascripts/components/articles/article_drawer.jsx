import React from 'react';
import Expandable from '../high_order/expandable.jsx';
import ArticleDetailsStore from '../../stores/article_details_store.js';
import DiffViewer from '../revisions/diff_viewer.jsx';
import Wp10Graph from './wp10_graph.jsx';

const getArticleDetails = () => ArticleDetailsStore.getArticleDetails();

const ArticleDrawer = React.createClass({
  displayName: 'ArticleDrawer',

  propTypes: {
    article: React.PropTypes.object,
    is_open: React.PropTypes.bool
  },

  mixins: [ArticleDetailsStore.mixin],

  getInitialState() {
    return {
      articleDetails: getArticleDetails()
    };
  },

  getKey() {
    return `drawer_${this.props.article.id}`;
  },

  storeDidChange() {
    return this.setState({
      articleDetails: getArticleDetails()
    });
  },

  render() {
    if (!this.props.is_open) { return <tr></tr>; }

    let className = 'drawer';
    className += !this.props.is_open ? ' closed' : '';

    let diffViewer;
    if (this.state.articleDetails.first_revision) {
      diffViewer = (
        <DiffViewer
          revision={this.state.articleDetails.last_revision}
          first_revision={this.state.articleDetails.first_revision}
          showButtonLabel={I18n.t('articles.show_cumulative_changes')}
          largeButton={true}
        />
      );
    } else {
      diffViewer = <button className="button dark">{I18n.t('articles.show_cumulative_changes')}</button>;
    }

    let editedBy;
    if (this.state.articleDetails.editors) {
      editedBy = <p>{I18n.t('articles.edited_by')} {this.state.articleDetails.editors.join(', ')}</p>;
    }

    return (
      <tr className={className}>
        <td colSpan="7">
          <span />
          <table className="table">
            <tbody>
              <tr>
                <td colSpan="4">
                  {diffViewer}
                </td>
                <td colSpan="3">
                  <Wp10Graph article={this.props.article} />
                </td>
              </tr>
              <tr>
                <td colSpan="7">
                  {editedBy}
                </td>
              </tr>
            </tbody>
          </table>
        </td>
      </tr>
    );
  }
});

export default Expandable(ArticleDrawer);
